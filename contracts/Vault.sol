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

import "hardhat/console.sol";

contract Vault {
    using SafeERC20 for ExternalERC20;

    // Parameters
    uint256 private constant secondsPerYear = 1; //31536000;

    address public immutable VADER;

    uint256 public minimumDepositTime;
    uint256 public totalWeight;

    mapping(address => uint256) private mapAsset_deposit;
    mapping(address => uint256) private mapAsset_balance;
    mapping(address => uint256) private mapAsset_lastHarvestedTime;
    mapping(address => uint256) private mapMember_weight;

    mapping(address => mapping(address => uint256)) private mapMemberAsset_deposit;
    mapping(address => mapping(address => uint256)) private mapMemberAsset_lastTime;

    // Events
    event MemberDeposits(
        address indexed asset,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event MemberWithdraws(
        address indexed asset,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event Harvests(
        address indexed asset,
        uint256 reward
    );

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "!DAO");
        _;
    }

    constructor(address _vader) {
        VADER = _vader;
        minimumDepositTime = 1;
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(
        uint256 newDepositTime
    ) external onlyDAO {
        minimumDepositTime = newDepositTime;
    }

    //======================================DEPOSITS========================================//

    // Deposit USDV or SYNTHS
    function deposit(address asset, uint256 amount) external  returns(uint256) {
        return depositForMember(asset, msg.sender, amount);
    }

    // Wrapper for contracts
    function depositForMember(
        address asset,
        address member,
        uint256 amount
    ) public returns(uint256){
        require(((iFACTORY(FACTORY()).isSynth(asset)) || asset == USDV()), "!Permitted"); // Only Synths or USDV
        require(iERC20(asset).transferFrom(msg.sender, address(this), amount));
        return _deposit(asset, member, amount);
    }

    function _deposit(
        address _asset,
        address _member,
        uint256 _amount
    ) internal returns(uint256 weight){
        mapMemberAsset_lastTime[_member][_asset] = block.timestamp; // Time of deposit
        mapMemberAsset_deposit[_member][_asset] += _amount; // Record deposit for member
        mapAsset_deposit[_asset] += _amount; // Record total deposit
        mapAsset_balance[_asset] = iERC20(_asset).balanceOf(address(this)); // sync deposits
        if(mapAsset_lastHarvestedTime[_asset] == 0){
            mapAsset_lastHarvestedTime[_asset] = block.timestamp;
        }
        if(_asset == USDV()){
            weight = _amount;
        } else {
            weight = iUTILS(UTILS()).calcSwapValueInBase(iSYNTH(_asset).TOKEN(), _amount);
        }
        mapMember_weight[_member] += weight; // Record total weight for member in USDV
        totalWeight += weight; // Total weight
        emit MemberDeposits(_asset, _member, _amount, weight, totalWeight);
        iRESERVE(RESERVE()).checkReserve();
    }

    //====================================== HARVEST ========================================//
    
    // Harvest, get reward, increase weight
    function harvest(address asset) external returns (uint256 reward) {
        reward = calcRewardForAsset(asset); 
        if (asset == USDV()) {
            iRESERVE(RESERVE()).requestFunds(USDV(), address(this), reward);
        } else {
            iRESERVE(RESERVE()).requestFunds(USDV(), POOLS(), reward);
            reward = iPOOLS(POOLS()).mintSynth(iSYNTH(asset).TOKEN(), address(this));
        }
        mapAsset_balance[asset] = iERC20(asset).balanceOf(address(this)); // sync deposits, now including the reward
        emit Harvests(asset, reward);
    }

    function calcRewardForAsset(address asset) public view returns(uint256 reward) {
        uint256 _owed = iRESERVE(RESERVE()).getVaultReward();
        uint256 _rewardsPerSecond = _owed / secondsPerYear; // Deplete over 1 year
        reward = (block.timestamp - mapAsset_lastHarvestedTime[asset]) * _rewardsPerSecond; // Multiply since last harvest
        if(reward > _owed){
            reward = _owed; // If too much
        }
        uint256 _weight = mapAsset_deposit[asset]; // Total Deposit
        if (asset != USDV()) {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(asset).TOKEN(), _weight);
        }
        reward = iUTILS(UTILS()).calcShare(_weight, totalWeight, reward); // Share of the reward
    }

    //====================================== WITHDRAW ========================================//

    // @title Withdraw `basisPoints` basis points of token `asset` from the vault to the caller.
    function withdraw(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount) {
        redeemedAmount = _processWithdraw(asset, msg.sender, basisPoints); // Get amount to withdraw
        iERC20(asset).transfer(msg.sender, redeemedAmount); // All assets are safe
    }

    // Withdraw to VADER
    function withdrawToVader(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount) {
        redeemedAmount = _processWithdraw(asset, msg.sender, basisPoints); // Get amount to withdraw
        if(asset != USDV()){
            redeemedAmount = iPOOLS(POOLS()).burnSynth(asset, address(this)); // Burn to USDV
        }
        iERC20(USDV()).approve(VADER, type(uint256).max);
        iVADER(VADER).redeemToVADERForMember(msg.sender, redeemedAmount); // Redeem to VADER for Member
    }

    function _processWithdraw(
        address _asset,
        address _member,
        uint256 _basisPoints
    ) internal returns (uint256 redeemedAmount) {
        require((block.timestamp - mapMemberAsset_lastTime[_member][_asset]) >= minimumDepositTime, "DepositTime"); // stops attacks
        redeemedAmount = iUTILS(UTILS()).calcPart(_basisPoints, calcDepositValueForMember(_asset, _member)); // Member share
        mapMemberAsset_deposit[_member][_asset] -= iUTILS(UTILS()).calcPart(_basisPoints, mapMemberAsset_deposit[_member][_asset]); // Reduce for member
        uint256 _redeemedWeight = redeemedAmount;
        if (_asset != USDV()) {
            _redeemedWeight = iUTILS(UTILS()).calcValueInBase(iSYNTH(_asset).TOKEN(), redeemedAmount);
            uint256 _memberWeight = mapMember_weight[_member];
            _redeemedWeight = iUTILS(UTILS()).calcShare(_redeemedWeight, _memberWeight, _memberWeight); // Safely reduce member weight
        }
        mapMember_weight[_member] -= _redeemedWeight; // Reduce for member
        totalWeight -= _redeemedWeight; // Reduce for total
        emit MemberWithdraws(_asset, _member, redeemedAmount, _redeemedWeight, totalWeight); // Event
        iRESERVE(RESERVE()).checkReserve();
    }

    // Get the value owed for a member
    function calcDepositValueForMember(address asset, address member) public view returns (uint256 value) {
        uint256 _memberDeposit = mapMemberAsset_deposit[member][asset];
        uint256 _totalDeposit = mapAsset_deposit[asset];
        uint256 _balance = mapAsset_balance[asset];
        value = iUTILS(UTILS()).calcShare(_memberDeposit, _totalDeposit, _balance); // Share of balance
    }

    //============================== HELPERS ================================//

    function reserveUSDV() external view returns (uint256) {
        return iRESERVE(RESERVE()).reserveUSDV(); // Balance
    }

    function reserveVADER() external view returns (uint256) {
        return iRESERVE(RESERVE()).reserveVADER(); // Balance
    }

    function getMemberDeposit(address member, address asset) external view returns (uint256) {
        return mapMemberAsset_deposit[member][asset];
    }

    function getMemberLastTime(address member, address asset) external view returns (uint256) {
        return mapMemberAsset_lastTime[member][asset];
    }

    function getMemberWeight(address member) external view returns (uint256) {
        return mapMember_weight[member];
    }

    function getAssetDeposit(address asset) external view returns (uint256) {
        return mapAsset_deposit[asset];
    }

    function getAssetLastTime(address asset) external view returns (uint256) {
        return mapAsset_lastHarvestedTime[asset];
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
