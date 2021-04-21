// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iROUTER.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iSYNTH.sol";

import "hardhat/console.sol";

contract USDV is iERC20 {

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint public override decimals; uint public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;

    // Parameters
    bool private inited;
    uint public nextEraTime;
    uint public erasToEarn;
    uint public minGrantTime;
    uint public lastGranted;
    uint public blockDelay;

    address public VADER;
    address public ROUTER;
    address public POOLS;

    uint public minimumDepositTime;
    uint public totalWeight;
    uint public totalRewards;

    mapping(address => uint) private mapToken_totalFunds;
    mapping(address => uint) private mapMember_weight;
    mapping(address => mapping(address => uint)) private mapMemberToken_deposit;
    mapping(address => mapping(address => uint)) private mapMemberToken_reward;
    mapping(address => mapping(address => uint)) private mapMemberToken_lastTime;
    mapping(address => uint) public lastBlock;

    // Events
    event MemberDeposits(address indexed token, address indexed member, uint newDeposit, uint totalDeposit, uint weight, uint totalWeight);
    event MemberWithdraws(address indexed token, address indexed member, uint amount, uint weight, uint totalWeight);
    event MemberHarvests(address indexed token, address indexed member, uint amount, uint weight, uint totalWeight);

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
    function isMature() public view returns(bool isMatured){
        if(lastBlock[tx.origin] + blockDelay <= block.number){ // Stops an EOA doing a flash attack in same block
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
    function init(address _vader, address _router, address _pool) external {
        require(inited == false);
        inited = true;
        VADER = _vader;
        ROUTER = _router;
        POOLS = _pool;
        iERC20(VADER).approve(ROUTER, type(uint).max);
        _approve(address(this), ROUTER, type(uint).max);
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
    function transfer(address recipient, uint amount) external virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    // iERC20 Approve, change allowance functions
    function approve(address spender, uint amount) external virtual override returns (bool) {
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
    function transferFrom(address sender, address recipient, uint amount) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    // TransferTo function
    // Risks: User can be phished, or tx.origin may be deprecated, optionality should exist in the system. 
    function transferTo(address recipient, uint amount) external virtual override returns (bool) {
        _transfer(tx.origin, recipient, amount);
        return true;
    }

    // Internal transfer function
    function _transfer(address sender, address recipient, uint amount) internal virtual {
        if(amount > 0){                                     // Due to design, this function may be called with 0
            require(sender != address(0), "sender");
            _balances[sender] -= amount;
            _balances[recipient] += amount;
            emit Transfer(sender, recipient, amount);
            _checkIncentives();
        }
    }
    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint amount) internal virtual {
        if(amount > 0){                                     // Due to design, this function may be called with 0
            require(account != address(0), "recipient");
            totalSupply += amount;
            _balances[account] += amount;
            emit Transfer(address(0), account, amount);
        }
    }
    // Burn supply
    function burn(uint amount) external virtual override {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint amount) external virtual override {
        uint decreasedAllowance = allowance(account, msg.sender)- amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }
    function _burn(address account, uint amount) internal virtual {
        if(amount > 0){                                     // Due to design, this function may be called with 0
            require(account != address(0), "address err");
            _balances[account] -= amount;
            totalSupply -= amount;
            emit Transfer(account, address(0), amount);
        }
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint newEra, uint newDepositTime, uint newDelay, uint newGrantTime) external onlyDAO {
        erasToEarn = newEra;
        minimumDepositTime = newDepositTime;
        blockDelay = newDelay;
        minGrantTime = newGrantTime;
    }

    // Can issue grants
    function grant(address recipient, uint amount) public onlyDAO {
        require(amount <= (reserveUSDV() / 10), "not more than 10%");
        require((block.timestamp - lastGranted) >= minGrantTime, "not too fast");
        lastGranted = block.timestamp;
        _transfer(address(this), recipient, amount); 
    }

   //======================================INCENTIVES========================================//
    // Internal - Update incentives function
    function _checkIncentives() private {
        if (block.timestamp >= nextEraTime && emitting()) {                 // If new Era
            nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra(); 
            uint _balance = iERC20(VADER).balanceOf(address(this));         // Get spare VADER
            uint _USDVShare = _twothirds(_balance);                         // Get 2/3rds
            _convert(address(this), _USDVShare);                            // Convert it
            _transfer(address(this), ROUTER, _USDVShare / 2);                        // Send USDV
            iERC20(VADER).transfer(ROUTER, iERC20(VADER).balanceOf(address(this)));  // Send VADER
        }
    }
    
    //======================================ASSET MINTING========================================//
    // Convert to USDV
    function convert(uint amount) external returns(uint) {
        return convertForMember(msg.sender, amount);
    }
    // Convert for members
    function convertForMember(address member, uint amount) public returns(uint) {
        getFunds(VADER, amount);
        return _convert(member, amount);
    }
    // Internal convert
    function _convert(address _member, uint amount) internal flashProof returns(uint _convertAmount){
        if(minting()){
            lastBlock[tx.origin] = block.number;                    // Record first
            iERC20(VADER).burn(amount);
            _convertAmount = iROUTER(ROUTER).getUSDVAmount(amount); // Critical pricing functionality
            _mint(_member, _convertAmount);
        }
    }
    // Redeem to VADER
    function redeem(uint amount) external returns(uint) {
        return redeemForMember(msg.sender, amount);
    }
    // Contracts to redeem for members
    function redeemForMember(address member, uint amount) public returns(uint redeemAmount) {
        _transfer(msg.sender, VADER, amount);                   // Move funds
        redeemAmount = iVADER(VADER).redeemToMember(member);    // Ask VADER to redeem
        lastBlock[tx.origin] = block.number;                    // Must record block AFTER the tx
    }

    //======================================DEPOSITS========================================//

    // Deposit USDV or SYNTHS
    function deposit(address token, uint amount) external {
        depositForMember(token, msg.sender, amount);
    }
    // Wrapper for contracts
    function depositForMember(address token, address member, uint amount) public {
        require(token==address(this) || (iPOOLS(POOLS).isSynth(token) && iPOOLS(POOLS).isAsset(iSYNTH(token).TOKEN()))); // Only USDV or Asset-Synths
        getFunds(token, amount);
        _deposit(token, member, amount);
    }
    function _deposit(address _token, address _member, uint _amount) internal {
        mapMemberToken_lastTime[_member][_token] = block.timestamp;         // Time of deposit
        mapMemberToken_deposit[_member][_token] += _amount;                 // Record deposit
        mapToken_totalFunds[_token] += _amount;                             // Total balance of that asset
        uint _weight;
        if(_token==address(this)){
            _weight = _amount;
        } else {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(_token).TOKEN(), _amount); // Convert synth to USDV value
        }
        mapMember_weight[_member] += _weight;   // Total member weight (normalised in USDV values)
        totalWeight += _weight;                 // Total weight (normalised in USDV values)
        emit MemberDeposits(_token, _member, _amount, mapToken_totalFunds[_token], _weight, totalWeight);
    }

    //====================================== HARVEST ========================================//

    // Harvest, get payment, allocate, increase weight
    function harvest(address token) external returns(uint reward) {
        address _member = msg.sender;
        reward = calcCurrentReward(token, _member);                     // In USDV
        mapMemberToken_lastTime[_member][token] = block.timestamp;      // Reset time
        mapMemberToken_reward[_member][token] += reward;                // Record separately
        totalRewards += reward;                                         // Accounting
        uint _weight;
        if(token==address(this)){
            _weight = reward;
        } else {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(token).TOKEN(), reward); // In USDV value
        }
        mapMember_weight[_member] += _weight;   // Increase member's voting weight
        totalWeight += _weight;                 // Increase total
        emit MemberHarvests(token, _member, reward, _weight, totalWeight);
    }

    // Get the payment owed for a member
    function calcCurrentReward(address token, address member) public view returns(uint reward) {
        uint _secondsSinceClaim = block.timestamp - mapMemberToken_lastTime[member][token];        // Get time since last claim
        uint _share = calcReward(member);                                               // Get share of rewards for member
        reward = (_share * _secondsSinceClaim) / iVADER(VADER).secondsPerEra();         // Get owed amount, based on per-day rates
        uint _reserve = reserveUSDV();
        if(reward >= _reserve) {
            reward = _reserve;                                                          // Send full reserve if the last
        }
    }

    function calcReward(address member) public view returns(uint) {
        uint _weight = mapMember_weight[member];                                    // Share of rewards based in USDV value
        uint _reserve = reserveUSDV() / erasToEarn;                                 // Deplete reserve over a number of eras
        return iUTILS(UTILS()).calcShare(_weight, totalWeight, _reserve);           // Get member's share of that
    }

//====================================== WITHDRAW ========================================//

    // Members to withdraw
    function withdraw(address token, uint basisPoints) external returns(uint redeemedAmount) {
        address _member = msg.sender;
        redeemedAmount = _processWithdraw(token, _member, basisPoints);          // Get amount to withdraw
        sendFunds(token, _member, redeemedAmount);
    }
    function _processWithdraw(address _token, address _member, uint _basisPoints) internal returns(uint _amount) {
        require((block.timestamp - mapMemberToken_lastTime[_member][_token]) >= minimumDepositTime, "DepositTime");    // stops attacks
        uint _reward = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberToken_reward[_member][_token]); // Share of reward (USDV)
        mapMemberToken_reward[_member][_token] -= _reward;                      // Reduce for member
        totalRewards -= _reward;                                                // Reduce for total
        if(_token!=address(this)){              // If synth, then need to swap to mint synth
            _transfer(address(this), POOLS, _reward);                                                   // Send Reward to POOLS
            _reward = iPOOLS(POOLS).mintSynth(address(this), iSYNTH(_token).TOKEN(), address(this));    // Mint to Synth, send back
        }
        uint _principle = iUTILS(UTILS()).calcPart(_basisPoints, mapMemberToken_deposit[_member][_token]); // Share of deposits
        mapMemberToken_deposit[_member][_token] -= _principle;                  // Reduce for member                             
        mapToken_totalFunds[_token] -= _principle;                              // Reduce for total
        uint _weight = iUTILS(UTILS()).calcPart(_basisPoints, mapMember_weight[_member]);   // Find recorded weight to reduce
        mapMember_weight[_member] -= _weight;                                   // Reduce for member    
        totalWeight -= _weight;                                                 // Reduce for total
        emit MemberWithdraws(_token, _member, _amount, _weight, totalWeight);   // Event
        return (_principle + _reward);                                          // Total to send to member
    }

    //============================== ASSETS ================================//

    function getFunds(address token, uint amount) internal {
        if(token == address(this)){
            _transfer(msg.sender, address(this), amount);
        } else {
            if(tx.origin==msg.sender){
                require(iERC20(token).transferTo(address(this), amount));
            }else{
                require(iERC20(token).transferFrom(msg.sender, address(this), amount));
            }
        }
    }
    function sendFunds(address token, address member, uint amount) internal {
        if(token == address(this)){
            _transfer(address(this), member, amount);
        } else {
            require(iERC20(token).transfer(member, amount));
        }
    }

    //============================== HELPERS ================================//

    function _twothirds(uint _amount) internal pure returns(uint){
        return (_amount * 2) / 3;
    }

    function reserveUSDV() public view returns(uint) {
        return balanceOf(address(this)) - mapToken_totalFunds[address(this)] - totalRewards; // Balance - deposits - rewards
    }
    function getTokenDeposits(address token) external view returns(uint) {
        return mapToken_totalFunds[token];
    }
    function getMemberDeposit(address token, address member) external view returns(uint){
        return mapMemberToken_deposit[member][token];
    }
    function getMemberReward(address token, address member) external view returns(uint){
        return mapMemberToken_reward[member][token];
    }
    function getMemberWeight(address member) external view returns(uint){
        return mapMember_weight[member];
    }
    function getMemberLastTime(address token, address member) external view returns(uint){
        return mapMemberToken_lastTime[member][token];
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
    function minting() public view returns(bool){
        return iVADER(VADER).minting();
    }

}