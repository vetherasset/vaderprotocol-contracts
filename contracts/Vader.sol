// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iUSDV.sol";
import "./iVAULT.sol";

    //======================================VADER=========================================//
contract Vader is iERC20 {
    using SafeMath for uint256;

    // ERC-20 Parameters
    string public override name; string public override symbol;
    uint256 public override decimals; uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Parameters
    uint256 _1m;
    uint256 public baseline;
    bool public emitting;
    uint256 public emissionCurve;
    uint256 public maxSupply;
    uint256 public secondsPerEra;
    uint256 public currentEra;
    uint256 public nextEraTime;

    address public VETHER;
    address public USDV;
    address public burnAddress;
    address public DAO;

    // Events
    event NewCurve(address indexed DAO, uint256 newCurve);
    event NewEra(uint256 currentEra, uint256 nextEraTime, uint256 emission);
    event NewDAO(address indexed DAO, address newOwner);
    event NewDuration(address indexed DAO, uint256 newDuration);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor(address _vether) public {
        name = 'VADER PROTOCOL TOKEN';
        symbol = 'VDR';
        decimals = 18;
        _1m = 10**6 * 10 ** decimals; //1m
        baseline = _1m;
        totalSupply = 0;
        maxSupply = 2 * _1m;
        emissionCurve = 2048;
        emitting = false;
        currentEra = 1;
        secondsPerEra = 1; //86400;
        nextEraTime = now + secondsPerEra;
        DAO = msg.sender;
        VETHER = _vether;
        burnAddress = 0x0111011001100001011011000111010101100101;
    }
    // Can set USDV
    function setUSDV(address _USDV) public{
        if(USDV == address(0)){
            USDV = _USDV;
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
        require(recipient != address(this), "recipient");
        _balances[sender] = _balances[sender].sub(amount, "balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        _checkEmission();
    }
    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "recipient");
        totalSupply = totalSupply.add(amount);
        require(totalSupply <= maxSupply, "maxSupply");
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
    function startEmissions() public onlyDAO returns(bool){
        emitting = true;
        return true;
    }
    // Can stop
    function stopEmissions() public onlyDAO returns(bool){
        emitting = false;
        return true;
    }
    // Can change emissionCurve
    function changeEmissionCurve(uint256 newCurve) public onlyDAO returns(bool){
        emissionCurve = newCurve;
        emit NewCurve(msg.sender, newCurve);
        return true;
    }
    // Can change daily time
    function changeEraDuration(uint256 newDuration) public onlyDAO returns(bool) {
        secondsPerEra = newDuration;
        emit NewDuration(msg.sender, newDuration);
        return true;
    }
    // Can change DAO
    function changeDAO(address newDAO) public onlyDAO returns(bool){
        require(newDAO != address(0), "address err");
        DAO = newDAO;
        emit NewDAO(msg.sender, newDAO);
        return true;
    }
    // Can purge DAO
    function purgeDAO() public onlyDAO returns(bool){
        DAO = address(0);
        emit NewDAO(msg.sender, address(0));
        return true;
    }

   //======================================EMISSION========================================//
    // Internal - Update emission function
    function _checkEmission() private {
        if ((now >= nextEraTime) && emitting) {                                            // If new Era and allowed to emit
            currentEra += 1;                                                               // Increment Era
            nextEraTime = now + secondsPerEra;                                             // Set next Era time
            uint256 _emission = getDailyEmission();                                        // Get Daily Dmission
            _mint(USDV, _emission);                                            // Mint to the Incentive Address
            emit NewEra(currentEra, nextEraTime, _emission);                               // Emit Event
        }
    }
    // Calculate Daily Emission
    function getDailyEmission() public view returns (uint256) {
        uint _adjustedMax;
        if(totalSupply <= baseline){ // If less than 1m, then adjust cap down
            _adjustedMax = (maxSupply.mul(totalSupply)).div(baseline); // 2m * 0.5m / 1m = 2m * 50% = 1.5m
        } else {
            _adjustedMax = maxSupply;  // 2m
        }
        return (_adjustedMax.sub(totalSupply)).div(emissionCurve); // outstanding / 2048 
    }
    //======================================ASSET MINTING========================================//
    // VETHER Owners to Upgrade
    function upgrade(uint amount) public {
        require(iERC20(VETHER).transferFrom(msg.sender, burnAddress, amount));
        _mint(msg.sender, amount);
    }
    // USDV Owners to redeem back to VDR
    function redeem(uint amount) public {
        require(iERC20(USDV).transferTo(address(this), amount));
        iERC20(USDV).burn(amount);
        uint _redeemAmount = iVAULT(iUSDV(USDV).VAULT()).getVDRAmount(amount);
        _mint(msg.sender, _redeemAmount);
    }
}