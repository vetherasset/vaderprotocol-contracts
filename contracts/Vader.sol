// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iERC677.sol"; 
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
    uint256 public nextEraTime;
    uint256 public feeOnTransfer;

    address public DAO;

    address public constant burnAddress = 0x0111011001100001011011000111010101100101;

    event NewEra(uint256 nextEraTime, uint256 emission);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "!DAO");
        _;
    }
    // Only TIMELOCK can execute
    modifier onlyTIMELOCK() {
        require(msg.sender == TIMELOCK(), "!TIMELOCK");
        _;
    }
    // Only DAO&&TIMELOCK can execute
    modifier onlyDAOandTIMELOCK() {
        require(msg.sender == DAO || msg.sender == TIMELOCK(), "!DAO && !TIMELOCK");
        _;
    }
    // Only VAULT can execute
    modifier onlyVAULT() {
        require(msg.sender == VAULT(), "!VAULT");
        _;
    }

    // notice A record of each accounts delegate
    mapping (address => address) public delegates;

    // @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    // @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    // @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    // @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    // @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    // @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    // @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    //=====================================CREATION=========================================//
 
    constructor() {
        secondsPerEra = 1; //86400;
        nextEraTime = block.timestamp + secondsPerEra;
        emissionCurve = 10;
        DAO = msg.sender; // Then call changeDAO() once DAO created
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
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender]+(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "allowance err");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "sender");
        require(spender != address(0), "spender");
        if (_allowances[owner][spender] < type(uint256).max) { // No need to re-approve if already max
            _allowances[owner][spender] = amount;
            emit Approval(owner, spender, amount);
        }
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
            uint256 currentAllowance = _allowances[sender][msg.sender];
            require(currentAllowance >= amount, "allowance err");
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }
    //iERC677 approveAndCall
    function approveAndCall(address recipient, uint amount, bytes calldata data) public returns (bool) {
      _approve(msg.sender, recipient, type(uint256).max); // Give recipient max approval
      iERC677(recipient).onTokenApproval(address(this), amount, msg.sender, data); // Amount is passed thru to recipient
      return true;
     }

      //iERC677 transferAndCall
    function transferAndCall(address recipient, uint amount, bytes calldata data) public returns (bool) {
      _transfer(msg.sender, recipient, amount);
      iERC677(recipient).onTokenTransfer(address(this), amount, msg.sender, data); // Amount is passed thru to recipient 
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
        require(_balances[sender] >= amount, "balance err");
        uint _fee = iUTILS(UTILS()).calcPart(feeOnTransfer, amount);  // Critical functionality
        if(_fee <= amount){                            // Stops reverts if UTILS corrupted
            amount -= _fee;
            _burn(sender, _fee);
        }
        _balances[sender] -= amount;
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
        require(_balances[account] >= amount, "balance err");
        _balances[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can start
    function flipEmissions() external onlyDAOandTIMELOCK {
        emitting = !emitting;
    }

    // Can stop
    function flipMinting() external onlyDAOandTIMELOCK {
        minting = !minting;
    }

    // Can set params
    function setParams(uint256 newEra, uint256 newCurve) external onlyDAOandTIMELOCK {
        secondsPerEra = newEra;
        emissionCurve = newCurve;
    }

    // Can change DAO
    function changeDAO(address newDAO) external onlyDAO {
        require(newDAO != address(0), "address err");
        DAO = newDAO;
    }

    // Can purge DAO
    function purgeDAO() external onlyTIMELOCK {
        DAO = address(0);
    }

    //======================================EMISSION========================================//
    // Internal - Update emission function
    function _checkEmission() private {
        if ((block.timestamp >= nextEraTime) && emitting) {
            // If new Era and allowed to emit
            nextEraTime = block.timestamp + secondsPerEra; // Set next Era time
            uint256 _emission = getDailyEmission(); // Get Daily Dmission
            _mint(RESERVE(), _emission); // Mint to the RESERVE Address
            feeOnTransfer = iUTILS(UTILS()).getFeeOnTransfer(totalSupply, maxSupply); // UpdateFeeOnTransfer
            if (feeOnTransfer > 1000) {
                feeOnTransfer = 1000;
            } // Max 10% if UTILS corrupted
            emit NewEra(nextEraTime, _emission); // Emit Event
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

    // Convert to USDV
    function convertToUSDV(uint256 amount) external returns (uint256) {
        return convertToUSDVForMember(msg.sender, amount);
    }

    // Convert for members
    function convertToUSDVForMember(address member, uint256 amount) public returns (uint256 convertAmount) {
        _transfer(msg.sender, USDV(), amount); // Move funds directly to USDV
        convertAmount = iUSDV(USDV()).convertToUSDVForMemberDirectly(member); // Ask USDV to convert
    }

    // Redeem back to VADER
    function redeemToVADER(uint256 amount) external onlyVAULT returns (uint256 redeemAmount) {
        return redeemToVADERForMember(msg.sender, amount);
    }

    // Redeem on behalf of member
    function redeemToVADERForMember(address member, uint256 amount) public onlyVAULT returns (uint256 redeemAmount) {
        require(minting, "not minting");
        require(iERC20(USDV()).transferFrom(msg.sender, address(this), amount));
        iERC20(USDV()).burn(amount);
        redeemAmount = iROUTER(ROUTER()).getVADERAmount(amount); // Critical pricing functionality
        _mint(member, redeemAmount);
    }

    //====================================== HELPERS ========================================//

    function VETHER() internal view returns(address){
        return iDAO(DAO).VETHER();
    }
    function USDV() internal view returns(address){
        return iDAO(DAO).USDV();
    }
    function VAULT() internal view returns(address){
        return iDAO(DAO).VAULT();
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
    function TIMELOCK() internal view returns(address){
        return iDAO(DAO).TIMELOCK();
    }

}
