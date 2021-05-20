// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "./interfaces/SafeERC20.sol";
import "./interfaces/iERC20.sol";
import "./interfaces/iDAO.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iROUTER.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iFACTORY.sol";
import "./interfaces/iSYNTH.sol";

contract Vault {
    using SafeERC20 for ExternalERC20;

    // Parameters
    uint256 public erasToEarn;
    uint256 public minGrantTime;

    address public immutable VADER;

    uint256 public minimumDepositTime;
    uint256 public totalWeight;

    mapping(address => uint256) private mapMember_weight;
    mapping(address => mapping(address => uint256)) private mapMemberSynth_weight;
    mapping(address => mapping(address => uint256)) private mapMemberSynth_deposit;
    mapping(address => mapping(address => uint256)) private mapMemberSynth_lastTime;

    // Events
    event MemberDeposits(
        address indexed synth,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event MemberWithdraws(
        address indexed synth,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event MemberHarvests(
        address indexed synth,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "!DAO");
        _;
    }

    constructor(address _vader) {
        VADER = _vader;
        erasToEarn = 100;
        minimumDepositTime = 1;
        minGrantTime = 2592000; // 30 days
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(
        uint256 newEra,
        uint256 newDepositTime,
        uint256 newGrantTime
    ) external onlyDAO {
        erasToEarn = newEra;
        minimumDepositTime = newDepositTime;
        minGrantTime = newGrantTime;
    }

    //======================================DEPOSITS========================================//

    // Deposit USDV or SYNTHS
    function deposit(address synth, uint256 amount) external {
        depositForMember(synth, msg.sender, amount);
    }

    // Wrapper for contracts
    function depositForMember(
        address synth,
        address member,
        uint256 amount
    ) public {
        require((iFACTORY(FACTORY()).isSynth(synth)), "Not Synth"); // Only Synths
        getFunds(synth, amount);
        _deposit(synth, member, amount);
    }

    function _deposit(
        address _synth,
        address _member,
        uint256 _amount
    ) internal {
        mapMemberSynth_lastTime[_member][_synth] = block.timestamp; // Time of deposit
        mapMemberSynth_deposit[_member][_synth] += _amount; // Record deposit
        uint256 _weight = iUTILS(UTILS()).calcSwapValueInBase(iSYNTH(_synth).TOKEN(), _amount);
        if (iPOOLS(POOLS()).isAnchor(iSYNTH(_synth).TOKEN())) {
            _weight = iROUTER(ROUTER()).getUSDVAmount(_weight); // Price in USDV
        }
        mapMemberSynth_weight[_member][_synth] += _weight;
        mapMember_weight[_member] += _weight; // Total member weight
        totalWeight += _weight; // Total weight
        emit MemberDeposits(_synth, _member, _amount, _weight, totalWeight);
        iRESERVE(RESERVE()).checkReserve();
    }

    //====================================== HARVEST ========================================//

    // Harvest, get payment, allocate, increase weight
    function harvest(address synth) external returns (uint256 reward) {
        address _member = msg.sender;
        uint256 _weight;
        address _token = iSYNTH(synth).TOKEN();
        reward = calcCurrentReward(synth, _member); // In USDV
        require(mapMemberSynth_weight[_member][synth] > 0, "must have deposited synth");
        mapMemberSynth_lastTime[_member][synth] = block.timestamp; // Reset time
        if (iPOOLS(POOLS()).isAsset(_token)) {
            iRESERVE(RESERVE()).requestFunds(USDV(), POOLS(), reward);
            reward = iPOOLS(POOLS()).mintSynth(USDV(), _token, address(this));
            _weight = iUTILS(UTILS()).calcValueInBase(_token, reward);
        } else {
            iRESERVE(RESERVE()).requestFunds(VADER, POOLS(), reward);
            reward = iPOOLS(POOLS()).mintSynth(VADER, _token, address(this));
            _weight = iROUTER(ROUTER()).getUSDVAmount(iUTILS(UTILS()).calcValueInBase(_token, reward));
        }
        mapMemberSynth_deposit[_member][synth] += reward;
        mapMember_weight[_member] += _weight;
        totalWeight += _weight;
        emit MemberHarvests(synth, _member, reward, _weight, totalWeight);
    }

    // Get the payment owed for a member
    function calcCurrentReward(address synth, address member) public view returns (uint256 reward) {
        uint256 _secondsSinceClaim = block.timestamp - mapMemberSynth_lastTime[member][synth]; // Get time since last claim
        uint256 _share = calcReward(member); // Get share of rewards for member
        reward = (_share * _secondsSinceClaim) / iVADER(VADER).secondsPerEra(); // Get owed amount, based on per-day rates
        uint256 _reserve;
        if (iPOOLS(POOLS()).isAsset(iSYNTH(synth).TOKEN())) {
            _reserve = reserveUSDV();
        } else {
            _reserve = reserveVADER();
        }
        if (reward >= _reserve) {
            reward = _reserve; // Send full reserve if the last
        }
    }

    function calcReward(address member) public view returns (uint256 reward) {
        uint256 _weight = mapMember_weight[member];
        uint256 _adjustedReserve = iROUTER(ROUTER()).getUSDVAmount(reserveVADER()) + reserveUSDV();
        return iUTILS(UTILS()).calcShare(_weight, totalWeight, _adjustedReserve / erasToEarn);
    }

    //====================================== WITHDRAW ========================================//

    // @title Withdraw `basisPoints` basis points of token `synth` from the vault to the caller.
    function withdraw(address synth, uint256 basisPoints) external returns (uint256 redeemedAmount) {
        redeemedAmount = _processWithdraw(synth, msg.sender, basisPoints); // Get amount to withdraw
        sendFunds(synth, msg.sender, redeemedAmount);
    }

    function _processWithdraw(
        address _synth,
        address _member,
        uint256 _basisPoints
    ) internal returns (uint256 redeemedAmount) {
        require((block.timestamp - mapMemberSynth_lastTime[_member][_synth]) >= minimumDepositTime, "DepositTime"); // stops attacks
        redeemedAmount = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberSynth_deposit[_member][_synth]); // Share of deposits
        mapMemberSynth_deposit[_member][_synth] -= redeemedAmount; // Reduce for member
        uint256 _weight = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberSynth_weight[_member][_synth]); // Find recorded weight to reduce
        mapMemberSynth_weight[_member][_synth] -= _weight; // Reduce for that synth
        mapMember_weight[_member] -= _weight; // Reduce for member
        totalWeight -= _weight; // Reduce for total
        emit MemberWithdraws(_synth, _member, redeemedAmount, _weight, totalWeight); // Event
        iRESERVE(RESERVE()).checkReserve();
    }

    //============================== ASSETS ================================//

    // @title Deposit tokens into this contract
    // @dev Assumes `synth` is trusted (is a synth token) and supports
    function getFunds(address synth, uint256 amount) internal {
        require(iERC20(synth).transferFrom(msg.sender, address(this), amount)); // safeErc20 not needed; synths trusted
    }

    // @title Send `amount` tokens of `synth` to `member`
    function sendFunds(
        address synth,
        address member,
        uint256 amount
    ) internal {
        ExternalERC20(synth).safeTransfer(member, amount); // use safeErc20 because caller (withdraw()) does not verify token is a synth
    }

    //============================== HELPERS ================================//

    function reserveUSDV() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveUSDV(); // Balance
    }

    function reserveVADER() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveVADER(); // Balance
    }

    function getMemberDeposit(address member, address synth) external view returns (uint256) {
        return mapMemberSynth_deposit[member][synth];
    }

    function getMemberSynthWeight(address member, address synth) external view returns (uint256) {
        return mapMemberSynth_weight[member][synth];
    }

    function getMemberWeight(address member) external view returns (uint256) {
        return mapMember_weight[member];
    }

    function getMemberLastTime(address member, address synth) external view returns (uint256) {
        return mapMemberSynth_lastTime[member][synth];
    }

    function DAO() internal view returns(address){
        return iVADER(VADER).DAO();
    }
    function USDV() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).USDV();
    }
    function RESERVE() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).RESERVE();
    }
    function ROUTER() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).ROUTER();
    }
    function POOLS() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).POOLS();
    }
    function FACTORY() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).FACTORY();
    }
    function UTILS() public view returns (address) {
        return iDAO(iVADER(VADER).DAO()).UTILS();
    }
}
