// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iROUTER.sol";

import "@nomiclabs/buidler/console.sol";

    //======================================VADER=========================================//
contract VSD is iERC20 {
    using SafeMath for uint256;

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint256 public override decimals; uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Parameters
    bool private inited;
    bool public emitting;
    uint256 public totalFunds;
    uint256 public currentEra;
    uint256 public nextEraTime;
    uint256 public erasToEarn;
    uint256 public minimumDepositTime;

    address public VADER;
    address public DAO;
    address public UTILS;
    address public ROUTER;

    mapping(address => bool) private _isMember; // Is Member
    mapping(address => uint256) private mapMember_deposit;
    mapping(address => uint256) private mapMember_lastTime;

    // Events
    event MemberDeposits(address indexed member, uint256 newDeposit, uint256 totalDeposit, uint256 totalFunds);
    event MemberWithdraws(address indexed member, uint256 amount, uint256 totalFunds);
    event MemberHarvests(address indexed member, uint256 amount);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor() public {
        name = 'VADER STABLE DOLLAR';
        symbol = 'VSD';
        decimals = 18;
        totalSupply = 0;
        DAO = msg.sender;
    }
    function init(address _vader, address _utils, address _router) public onlyDAO {
        require(inited == false);
        VADER = _vader;
        UTILS = _utils;
        ROUTER = _router;
        iERC20(VADER).approve(ROUTER, uint(-1));
        _approve(address(this), ROUTER, uint(-1));
        currentEra = 1;
        nextEraTime = now + iVADER(VADER).secondsPerEra();
        erasToEarn = 100;
        minimumDepositTime = 1;
    }

    //========================================iERC20=========================================//
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }
    // iERC20 Transfer function
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    // iERC20 Approve, change allowance functions
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    // iERC20 TransferFrom function
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "allowance"));
        return true;
    }

    // TransferTo function
    function transferTo(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(tx.origin, recipient, amount);
        return true;
    }

    // Internal transfer function
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "sender");
        _balances[sender] = _balances[sender].sub(amount, "balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        _checkIncentives();
    }
    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "recipient");
        totalSupply = totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
    // Burn supply
    function burn(uint256 amount) public virtual override {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint256 amount) public virtual override {
        uint256 decreasedAllowance = allowance(account, msg.sender).sub(amount, "allowance");
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "address err");
        _balances[account] = _balances[account].sub(amount, "balance");
        totalSupply = totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can start
    function startEmissions() public onlyDAO{
        emitting = true;
    }
    // Can stop
    function stopEmissions() public onlyDAO{
        emitting = false;
    }
    // Can set params
    function setParams(uint _one, uint _two) public onlyDAO {
        erasToEarn = _one;
        minimumDepositTime = _two;//8640000; //100 days
    }
    // Can change DAO
    function changeDAO(address newDAO) public onlyDAO{
        require(newDAO != address(0), "address err");
        DAO = newDAO;
    }
    // Can purge DAO
    function purgeDAO() public onlyDAO{
        DAO = address(0);
    }

   //======================================INCENTIVES========================================//
    // Internal - Update incentives function
    function _checkIncentives() private {
        if (now >= nextEraTime && emitting) {                  // If new Era
            currentEra += 1;                                                               // Increment Era
            nextEraTime = now + iVADER(VADER).secondsPerEra(); 
            uint _balance = iERC20(VADER).balanceOf(address(this)); // Get spare VADER
            uint _VSDShare = _twothirds(_balance);                 // Get 2/3rds
            _convert(_VSDShare);                                   // Convert it
            iROUTER(ROUTER).pullIncentives(iERC20(VADER).balanceOf(address(this)), _VSDShare.div(2));                         // Pull incentives over
        }
    }
    
    //======================================ASSET MINTING========================================//
    // VADER Holders to convert to VSD
    function convert(uint amount) public returns(uint convertAmount) {
        require(iERC20(VADER).transferTo(address(this), amount));   // Get funds
        convertAmount = _convert(amount);                           // Get conversion amount, mint here
        _deposit(msg.sender, convertAmount);                        // Deposit for member in vault
        return convertAmount;
    }
    // Internal convert
    function _convert(uint amount) internal returns(uint _convertAmount){
        iERC20(VADER).burn(amount);
        _convertAmount = iROUTER(ROUTER).getVSDAmount(amount);
        _mint(address(this), _convertAmount);
        return _convertAmount;
    }
    //======================================VSD DEPOSITS========================================//
    // VSD holders to deposit for Interest Payments
    function deposit(uint amount) public {
        depositForMember(msg.sender, amount);
    }
    // Wrapper for contracts
    function depositForMember(address member, uint amount) public {
        require(transferTo(address(this), amount));
        _deposit(member, amount);
    }
    // Harvest, then re-invest
    function harvestAndDeposit() public {
        address member = msg.sender;
        uint _payment = calcCurrentPayment(member);
        _deposit(member, _payment);
    }
    function _deposit(address _member, uint _amount) internal {
        if (!isMember(_member)) {
            _isMember[_member] = true;
        }
        mapMember_lastTime[_member] = now;
        mapMember_deposit[_member] = mapMember_deposit[_member].add(_amount); // Record balance for member
        totalFunds = totalFunds.add(_amount);
        emit MemberDeposits(_member, _amount, mapMember_deposit[_member], totalFunds);
    }

    // Harvest, get rewards immediately
    function harvest() public {
        address member = msg.sender;
        uint _payment = calcCurrentPayment(member);
        mapMember_lastTime[member] = now;
        _transfer(address(this), member, _payment);
        emit MemberHarvests(member, _payment);
    }

    // Get the payment owed for a member
    function calcCurrentPayment(address member) public view returns(uint){
        uint _secondsSinceClaim = now.sub(mapMember_lastTime[member]);      // Get time since last claim
        uint _share = calcPayment(member);                                  // Get share of rewards for member
        uint _reward = _share.mul(_secondsSinceClaim).div(iVADER(VADER).secondsPerEra());   // Get owed amount, based on per-day rates
        uint _reserve = reserveVSD();
        if(_reward >= _reserve) {
            _reward = _reserve;                                             // Send full reserve if the last
        }
        return _reward;
    }

    function calcPayment(address member) public view returns(uint){
        uint _balance = mapMember_deposit[member];
        uint _reserve = reserveVSD().div(erasToEarn);                          // Deplete reserve over a number of days
        return iUTILS(UTILS).calcShare(_balance, totalFunds, _reserve);         // Get member's share of that
    }

    // Members to withdraw to VSD
    function withdrawToVSD(uint basisPoints) public returns(uint redeemedAmount) {
        address _member = msg.sender;
        redeemedAmount = _processWithdraw(_member, basisPoints);                         // get VSD to withdraw
        _transfer(address(this), msg.sender, redeemedAmount);                    // Forward to member
        return redeemedAmount;
    }
    // Members to withdraw to VADER
    function withdrawToVADER(uint basisPoints) public returns(uint redeemedAmount) {
        address _member = msg.sender;
        uint _withdrawnAmount = _processWithdraw(_member, basisPoints);              // get VSD to withdraw
        _transfer(address(this), VADER, _withdrawnAmount);                      // send to VADER
        redeemedAmount = iVADER(VADER).redeem();                                // Vader burns VSD to VADER, sends back
        iERC20(VADER).transfer(_member, redeemedAmount);                        // Forward to member
        return redeemedAmount;
    }
    function _processWithdraw(address _member, uint basisPoints) internal returns(uint _amount) {
        require(now.sub(mapMember_lastTime[_member]) >= minimumDepositTime, "DepositTime");    // stops attacks
        harvestAndDeposit();                                                    // harvest first
        _amount = (mapMember_deposit[_member].mul(basisPoints)).div(10000);     // In Basis Points
        mapMember_deposit[_member] = mapMember_deposit[_member].sub(_amount);   // reduce for member
        totalFunds = totalFunds.sub(_amount);                                   // reduce for total
        emit MemberWithdraws(_member, _amount, totalFunds);
        return _amount;
    }


    //============================== HELPERS ================================//

    function reserveVSD() public view returns(uint){
        return balanceOf(address(this)).sub(totalFunds);
    }

    function _twothirds(uint _amount) internal pure returns(uint){
        return (_amount.mul(2)).div(3);
    }
    function getMemberDeposit(address member) public view returns(uint){
        return mapMember_deposit[member];
    }
    function getMemberLastTime(address member) public view returns(uint){
        return mapMember_lastTime[member];
    }
    function isMember(address member) public view returns(bool){
        return _isMember[member];
    }

}