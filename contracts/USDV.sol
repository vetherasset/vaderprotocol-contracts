// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iVAULT.sol";
import "./iUTILS.sol";

    //======================================VADER=========================================//
contract USDV is iERC20 {
    using SafeMath for uint256;

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint256 public override decimals; uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Parameters
    uint256 one;
    uint256 public totalFunds;
    uint256 public secondsPerEra;
    uint256 public currentEra;
    uint256 public nextEraTime;
    uint256 public erasToEarn;

    address public VADER;
    address public VAULT;
    address public DAO;
    address public UTILS;

    mapping(address => bool) public isMember; // Is Member
    mapping(address => uint256) public mapMember_deposit;
    mapping(address => uint256) public mapMember_lastTime;

    // Events
    event MemberDeposits(address indexed member, uint256 amount, uint256 totalFunds);
    event MemberWithdraws(address indexed member, uint256 amount, uint256 totalFunds);
    event MemberHarvests(address indexed member, uint256 payment);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor(address _vader, address _utils) public {
        name = 'USD - VADER PROTOCOL';
        symbol = 'USDv';
        decimals = 18;
        one = 10 ** decimals;
        totalSupply = 0;
        DAO = msg.sender;
        VADER = _vader;
        UTILS = _utils;
        currentEra = 1;
        secondsPerEra = 1; //86400;
        erasToEarn = 100;
        nextEraTime = now + secondsPerEra;
    }

    // Can set vault
    function setVault(address _vault) public {
        if(VAULT == address(0)){
            VAULT = _vault;
        }
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

   //======================================INCENTIVES========================================//
    // Internal - Update incentives function
    function _checkIncentives() private {
        if ((now >= nextEraTime)) {                                 // If new Era
            currentEra += 1;                                        // Increment Era
            nextEraTime = now + secondsPerEra;                      // Set next Era time
            uint _balance = iERC20(VADER).balanceOf(address(this)); // Get spare VADER
            uint _USDVShare = _twothirds(_balance);                 // Get 2/3rds
            _convert(_USDVShare);                                   // Convert it
            iVAULT(VAULT).pullIncentives(iERC20(VADER).balanceOf(address(this)), _USDVShare.div(2));                         // Pull incentives over
        }
    }
    
    //======================================ASSET MINTING========================================//
    // VADER Holders to convert to USDv
    function convert(uint amount) public returns(uint convertAmount) {
        require(iERC20(VADER).transferTo(address(this), amount));
        iERC20(VADER).burn(amount);
        convertAmount = iVAULT(VAULT).getUSDVAmount(amount);
        _mint(msg.sender, convertAmount);
        return convertAmount;
    }

    // Internal convert
    function _convert(uint amount) internal {
        iERC20(VADER).burn(amount);
        uint _convertAmount = iVAULT(VAULT).getUSDVAmount(amount);
        _mint(address(this), _convertAmount);
    }
    //======================================USDV DEPOSITS========================================//
    // USDV holders to deposit for Interest Payments
    function deposit(uint amount) public {
        depositForMember(msg.sender, amount);
    }
    // Wrapper for contracts
    function depositForMember(address member, uint amount) public {
        require(transferTo(address(this), amount));
        if (!isMember[member]) {
            mapMember_lastTime[member] = now;
            isMember[member] = true;
        }
        mapMember_deposit[member] = mapMember_deposit[member].add(amount); // Record balance for member
        totalFunds = totalFunds.add(amount);
        emit MemberDeposits(member, amount, totalFunds);
    }

    // Harvest, then re-invest
    function harvestAndDeposit() public {
        address member = msg.sender;
        _checkIncentives(); //
        uint _payment = calcCurrentPayment(member);
        mapMember_lastTime[member] = now;
        mapMember_deposit[member] = mapMember_deposit[member].add(_payment); // Record balance for member
        totalFunds = totalFunds.add(_payment);
        emit MemberHarvests(member, _payment);
        emit MemberDeposits(member, _payment, totalFunds);
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
        uint _secondsSinceClaim = now.sub(mapMember_lastTime[member]); // Get time since last claim
        uint _share = calcPayment(member);    // get share of rewards for member
        uint _reward = _share.mul(_secondsSinceClaim).div(secondsPerEra);    // Get owed amount, based on per-day rates
        uint _reserve = reserveUSDV();
        if(_reward >= _reserve) {
            _reward = _reserve; // Send full reserve if the last person
        }
        return _reward;
    }

    function calcPayment(address member) public view returns(uint){
        uint _balance = mapMember_deposit[member];
        uint _reserve = reserveUSDV().div(erasToEarn); // Aim to deplete reserve over a number of days
        return iUTILS(UTILS).calcShare(_balance, totalFunds, _reserve); // Get member's share of that
    }

    // Member withdraws 
    function withdraw(uint basisPoints) public {
        address member = msg.sender;
        harvestAndDeposit(); // harvest first
        uint _amount = (mapMember_deposit[member].mul(basisPoints)).div(10000); // In Basis Points
        mapMember_deposit[member] = mapMember_deposit[member].sub(_amount); // reduce for member
        totalFunds = totalFunds.sub(_amount); // reduce for total
        _transfer(address(this), member, _amount);
        emit MemberWithdraws(member, _amount, totalFunds);
    }

    //============================== HELPERS ================================//

    function reserveUSDV() public view returns(uint){
        return balanceOf(address(this)).sub(totalFunds);
    }

    function _twothirds(uint _amount) internal pure returns(uint){
        return (_amount.mul(2)).div(3);
    }

}