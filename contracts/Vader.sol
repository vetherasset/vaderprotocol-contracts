// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iDAO.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iUSDV.sol";
import "./interfaces/iROUTER.sol";

contract Vader is iERC20 {
    // ERC-20 Parameters
    string public constant override name = "VADER PROTOCOL TOKEN";
    string public constant override symbol = "VADER";
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Parameters
     
    bool public emitting;
    bool public minting;
    uint256 public constant conversionFactor = 1000;
    uint256 public constant baseline = 10**9 * 10**decimals; //1bn;
    uint256 public constant maxSupply = 2 * baseline; //2bn
    uint256 public emissionCurve;
    uint256 public secondsPerEra;
    uint256 public currentEra;
    uint256 public nextEraTime;
    uint256 public feeOnTransfer;

    address public DAO;
    address public DEPLOYER;

    address public constant burnAddress = 0x0111011001100001011011000111010101100101;

    event NewEra(uint256 currentEra, uint256 nextEraTime, uint256 emission);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO || msg.sender == DEPLOYER, "Not DAO");
        _;
    }
    // Stop flash attacks
    modifier flashProof() {
        require(isMature(), "No flash");
        _;
    }

    function isMature() public view returns (bool) {
        return iUSDV(USDV()).isMature();
    }

    //=====================================CREATION=========================================//
 
    constructor() {
        currentEra = 1;
        secondsPerEra = 1; //86400;
        nextEraTime = block.timestamp + secondsPerEra;
        emissionCurve = 10;
        DEPLOYER = msg.sender;
    }

    function init(address _dao) external {
        if(DAO == address(0)){
            DAO = _dao;
        }
    }

    //========================================iERC20=========================================//
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    // iERC20 Transfer function
    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    // iERC20 Approve, change allowance functions
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // iERC20 TransferFrom function
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        // Unlimited approval (saves an SSTORE)
        if (_allowances[sender][msg.sender] < type(uint256).max) {
            _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        }
        return true;
    }

    // TransferTo function
    // Risks: User can be phished, or tx.origin may be deprecated, optionality should exist in the system.
    function transferTo(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(tx.origin, recipient, amount);
        return true;
    }

    // Internal transfer function
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "sender");
        require(recipient != address(this), "recipient");
        _balances[sender] -= amount;
        uint _fee = iUTILS(UTILS()).calcPart(feeOnTransfer, amount);  // Critical functionality
        if(_fee <= amount){                            // Stops reverts if UTILS corrupted
            amount -= _fee;
            _burn(sender, _fee);
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        _checkEmission();
    }

    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "recipient");
        if ((totalSupply + amount) > maxSupply) {
            amount = maxSupply - totalSupply; // Safety, can't mint above maxSupply
        }
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    // Burn supply
    function burn(uint256 amount) external virtual override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external virtual override {
        uint256 decreasedAllowance = allowance(account, msg.sender) - amount;
        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "address err");
        _balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can start
    function flipEmissions() external onlyDAO {
        emitting = !emitting;
    }

    // Can stop
    function flipMinting() external onlyDAO {
        minting = !minting;
    }

    // Can set params
    function setParams(uint256 newEra, uint256 newCurve) external onlyDAO {
        secondsPerEra = newEra;
        emissionCurve = newCurve;
    }

    // Can change DAO
    function changeDAO(address newDAO) external onlyDAO {
        require(newDAO != address(0), "address err");
        DAO = newDAO;
    }

    // Can purge DAO
    function purgeDAO() external onlyDAO {
        DAO = address(0);
    }

    //======================================EMISSION========================================//
    // Internal - Update emission function
    function _checkEmission() private {
        if ((block.timestamp >= nextEraTime) && emitting) {
            // If new Era and allowed to emit
            currentEra += 1; // Increment Era
            nextEraTime = block.timestamp + secondsPerEra; // Set next Era time
            uint256 _emission = getDailyEmission(); // Get Daily Dmission
            _mint(RESERVE(), _emission); // Mint to the RESERVE Address
            feeOnTransfer = iUTILS(UTILS()).getFeeOnTransfer(totalSupply, maxSupply); // UpdateFeeOnTransfer
            if (feeOnTransfer > 1000) {
                feeOnTransfer = 1000;
            } // Max 10% if UTILS corrupted
            emit NewEra(currentEra, nextEraTime, _emission); // Emit Event
        }
    }

    // Calculate Daily Emission
    function getDailyEmission() public view returns (uint256) {
        uint256 _adjustedMax;
        if (totalSupply <= baseline) {
            // If less than 1bn, then adjust cap down
            _adjustedMax = (maxSupply * totalSupply) / baseline; // 2bn * 0.5m / 1m = 2m * 50% = 1.5m
        } else {
            _adjustedMax = maxSupply; // 2bn
        }
        return (_adjustedMax - totalSupply) / (emissionCurve); // outstanding / curve
    }

    //======================================ASSET MINTING========================================//
    // VETHER Owners to Upgrade
    function upgrade(uint256 amount) external {
        require(iERC20(VETHER()).transferFrom(msg.sender, burnAddress, amount)); // safeERC20 not needed; vether trusted
        _mint(msg.sender, amount * conversionFactor);
    }

    // Directly redeem back to VADER (must have sent USDV first)
    function redeem() external returns (uint256 redeemAmount) {
        return redeemToMember(msg.sender);
    }

    // Redeem on behalf of member (must have sent USDV first)
    function redeemToMember(address member) public flashProof returns (uint256 redeemAmount) {
        require(minting, "not minting");
        uint256 _amount = iERC20(USDV()).balanceOf(address(this));
        iERC20(USDV()).burn(_amount);
        redeemAmount = iROUTER(ROUTER()).getVADERAmount(_amount); // Critical pricing functionality
        _mint(member, redeemAmount);
    }

    //====================================== HELPERS ========================================//

    function VETHER() internal view returns(address){
        return iDAO(DAO).VETHER();
    }
    function USDV() internal view returns(address){
        return iDAO(DAO).USDV();
    }
    function RESERVE() internal view returns(address){
        return iDAO(DAO).RESERVE();
    }
    function ROUTER() internal view returns(address){
        return iDAO(DAO).ROUTER();
    }
    function UTILS() internal view returns(address){
        return iDAO(DAO).UTILS();
    }

}
