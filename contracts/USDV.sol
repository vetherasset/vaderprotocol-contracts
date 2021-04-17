// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iROUTER.sol";

    //======================================VADER=========================================//
contract USDV is iERC20 {

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint public override decimals; uint public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;

    // Parameters
    bool private inited;
    uint public totalFunds;
    uint public currentEra;
    uint public nextEraTime;
    uint public erasToEarn;
    uint public minimumDepositTime;
    uint public minGrantTime;
    uint public lastGranted;
    uint public blockDelay;

    address public VADER;
    address public ROUTER;

    mapping(address => bool) private _isMember; // Is Member
    mapping(address => uint) private mapMember_deposit;
    mapping(address => uint) private mapMember_lastTime;
    mapping(address => uint) public lastBlock;

    // Events
    event MemberDeposits(address indexed member, uint newDeposit, uint totalDeposit, uint totalFunds);
    event MemberWithdraws(address indexed member, uint amount, uint totalFunds);
    event MemberHarvests(address indexed member, uint amount);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "Not DAO");
        _;
    }
    // Stop flash attacks
    modifier flashProof() {
        require(isMature(), "No flash");
        _;
    }
    function isMature() public view returns(bool matured){
        if(lastBlock[tx.origin] + blockDelay <= block.number){
            return true;
        }
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor() {
        name = 'VADER STABLE DOLLAR';
        symbol = 'USDV';
        decimals = 18;
        totalSupply = 0;
    }
    function init(address _vader, address _router) public {
        require(!inited);
        VADER = _vader;
        ROUTER = _router;
        iERC20(VADER).approve(ROUTER, type(uint).max);
        _approve(address(this), ROUTER, type(uint).max);
        currentEra = 1;
        nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra();
        erasToEarn = 100;
        minimumDepositTime = 1;
        blockDelay = 0;
        minGrantTime = 2592000;     // 30 days
    }

    //========================================iERC20=========================================//
    function balanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }
    function allowance(address owner, address spender) public view virtual override returns (uint) {
        return _allowances[owner][spender];
    }
    // iERC20 Transfer function
    function transfer(address recipient, uint amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    // iERC20 Approve, change allowance functions
    function approve(address spender, uint amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function _approve(address owner, address spender, uint amount) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    // iERC20 TransferFrom function
    function transferFrom(address sender, address recipient, uint amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    // TransferTo function
    function transferTo(address recipient, uint amount) public virtual override returns (bool) {
        _transfer(tx.origin, recipient, amount);
        return true;
    }

    // Internal transfer function
    function _transfer(address sender, address recipient, uint amount) internal virtual {
        require(sender != address(0), "sender");
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        _checkIncentives();
    }
    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint amount) internal virtual {
        require(account != address(0), "recipient");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    // Burn supply
    function burn(uint amount) public virtual override {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint amount) public virtual override {
        uint decreasedAllowance = allowance(account, msg.sender)- amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }
    function _burn(address account, uint amount) internal virtual {
        require(account != address(0), "address err");
        _balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint _one, uint _two, uint _three, uint _four) public onlyDAO {
        erasToEarn = _one;
        minimumDepositTime = _two;
        blockDelay = _three;
        minGrantTime = _four;
    }
    // Can set params
    function grant(address recipient, uint amount) public onlyDAO {
        require(amount <= (reserveUSDV() / 10), "not more than 10%");
        require((block.timestamp - lastGranted) >= minGrantTime, "not too fast");
        _transfer(address(this), recipient, amount); 
    }

   //======================================INCENTIVES========================================//
    // Internal - Update incentives function
    function _checkIncentives() private {
        if (block.timestamp >= nextEraTime && emitting()) {                  // If new Era
            currentEra += 1;                                        // Increment Era
            nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra(); 
            uint _balance = iERC20(VADER).balanceOf(address(this)); // Get spare VADER
            uint _USDVShare = _twothirds(_balance);                 // Get 2/3rds
            _convert(address(this), _USDVShare);                    // Convert it
            iROUTER(ROUTER).pullIncentives(iERC20(VADER).balanceOf(address(this)), _USDVShare / 2);                         // Pull incentives over
        }
    }
    
    //======================================ASSET MINTING========================================//
    // Contracts to convert
    function convertToUSDV(uint amount) public returns(uint) {
        return convertToUSDVForMember(msg.sender, amount);
    }
    // Contracts to convert for members
    function convertToUSDVForMember(address member, uint amount) public returns(uint) {
        uint _safeAmount = getFunds(amount);
        return _convert(member, _safeAmount);
    }
    function getFunds(uint amount) public returns(uint safeAmount){
        uint _startBal = iERC20(VADER).balanceOf(address(this));
        if(tx.origin==msg.sender){
            require(iERC20(VADER).transferTo(address(this), amount));
        }else{
            require(iERC20(VADER).transferFrom(msg.sender, address(this), amount));
        }
        return (iERC20(VADER).balanceOf(address(this)) - _startBal);
    }
    // Internal convert
    function _convert(address _member, uint amount) internal flashProof returns(uint _convertAmount){
        lastBlock[tx.origin] = block.number;
        iERC20(VADER).burn(amount);
        _convertAmount = iROUTER(ROUTER).getUSDVAmount(amount);
        _mint(_member, _convertAmount);
        return _convertAmount;
    }
    // Contracts to redeem
    function redeemToVADER(uint amount) public returns(uint convertAmount) {
        return redeemToVADERForMember(msg.sender, amount);
    }
    // Contracts to redeem for members
    function redeemToVADERForMember(address member, uint amount) public returns(uint redeemAmount) {
        _transfer(msg.sender, VADER, amount);                   // Move funds
        redeemAmount = iVADER(VADER).redeemToMember(member);
        lastBlock[tx.origin] = block.number;
        return redeemAmount;
    }

    //======================================USDV DEPOSITS========================================//
    // USDV holders to deposit for Interest Payments
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
        mapMember_lastTime[_member] = block.timestamp;
        mapMember_deposit[_member] += _amount; // Record balance for member
        totalFunds += _amount;
        emit MemberDeposits(_member, _amount, mapMember_deposit[_member], totalFunds);
    }

    // Harvest, get rewards immediately
    function harvest() public {
        address member = msg.sender;
        uint _payment = calcCurrentPayment(member);
        mapMember_lastTime[member] = block.timestamp;
        _transfer(address(this), member, _payment);
        emit MemberHarvests(member, _payment);
    }

    // Get the payment owed for a member
    function calcCurrentPayment(address member) public view returns(uint){
        uint _secondsSinceClaim = block.timestamp - mapMember_lastTime[member];        // Get time since last claim
        uint _share = calcPayment(member);                                              // Get share of rewards for member
        uint _reward = (_share * _secondsSinceClaim) / iVADER(VADER).secondsPerEra();   // Get owed amount, based on per-day rates
        uint _reserve = reserveUSDV();
        if(_reward >= _reserve) {
            _reward = _reserve;                                                         // Send full reserve if the last
        }
        return _reward;
    }

    function calcPayment(address member) public view returns(uint){
        uint _balance = mapMember_deposit[member];
        uint _reserve = (reserveUSDV() / erasToEarn);                          // Deplete reserve over a number of days
        return iUTILS(UTILS()).calcShare(_balance, totalFunds, _reserve);         // Get member's share of that
    }

    // Members to withdraw
    function withdraw(uint basisPoints) public returns(uint redeemedAmount) {
        address _member = msg.sender;
        redeemedAmount = _processWithdraw(_member, basisPoints);                         // get USDV to withdraw
        _transfer(address(this), msg.sender, redeemedAmount);                    // Forward to member
        return redeemedAmount;
    }
    function _processWithdraw(address _member, uint basisPoints) internal returns(uint _amount) {
        require((block.timestamp - mapMember_lastTime[_member]) >= minimumDepositTime, "DepositTime");    // stops attacks
        harvestAndDeposit();                                                    // harvest first
        _amount = ((mapMember_deposit[_member] * basisPoints)) / 10000;         // In Basis Points
        mapMember_deposit[_member] -= _amount;                                  // reduce for member
        totalFunds -= _amount;                                                  // reduce for total
        emit MemberWithdraws(_member, _amount, totalFunds);
        return _amount;
    }

    //============================== HELPERS ================================//

    function reserveUSDV() public view returns(uint){
        return balanceOf(address(this)) - totalFunds;
    }

    function _twothirds(uint _amount) internal pure returns(uint){
        return (_amount * 2) / 3;
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
    function UTILS() public view returns(address){
        return iVADER(VADER).UTILS();
    }
    function DAO() public view returns(address){
        return iVADER(VADER).DAO();
    }
    function emitting() public view returns(bool){
        return iVADER(VADER).emitting();
    }

}
