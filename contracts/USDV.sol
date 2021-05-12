// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iERC677.sol"; 
import "./interfaces/iDAO.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iROUTER.sol";

contract USDV is iERC20 {
    // ERC-20 Parameters
    string public constant override name = "VADER STABLE DOLLAR";
    string public constant override symbol = "USDV";
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Parameters
    uint256 public blockDelay;

    address public VADER;

    mapping(address => uint256) public lastBlock;

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "!DAO");
        _;
    }
    // Stop flash attacks
    modifier flashProof() {
        require(isMature(), "No flash");
        _;
    }

    function isMature() public view returns (bool isMatured) {
        if (lastBlock[tx.origin] + blockDelay <= block.number) {
            // Stops an EOA doing a flash attack in same block
            return true;
        }
    }

    //=====================================CREATION=========================================//

    constructor() {}

    function init(address _vader) external {
        if (VADER == address(0)) {
            VADER = _vader;
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
        if (amount > 0) {
            // Due to design, this function may be called with 0
            require(sender != address(0), "sender");
            require(recipient != address(this), "recipient");
            require(_balances[sender] >= amount, "balance err");
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
    }

    // Internal mint (upgrading and daily emissions)
    function _mint(address account, uint256 amount) internal virtual {
        if (amount > 0) {
            // Due to design, this function may be called with 0
            require(account != address(0), "recipient");
            totalSupply += amount;
            _balances[account] += amount;
        }
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
        if (amount > 0) {
            // Due to design, this function may be called with 0
            require(account != address(0), "address err");
            require(_balances[account] >= amount, "balance err");
            _balances[account] -= amount;
            totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint256 newDelay) external onlyDAO {
        blockDelay = newDelay;
    }

    //======================================ASSET MINTING========================================//
    // Convert to USDV
    function convert(uint256 amount) external returns (uint256) {
        return convertForMember(msg.sender, amount);
    }

    // Convert for members
    function convertForMember(address member, uint256 amount) public returns (uint256) {
        getFunds(VADER, amount);
        return _convert(member, amount);
    }

    // Internal convert
    function _convert(address _member, uint256 amount) internal flashProof returns (uint256 _convertAmount) {
        require(iVADER(VADER).minting(), "not minting");
        lastBlock[tx.origin] = block.number; // Record first
        iERC20(VADER).burn(amount);
        _convertAmount = iROUTER(ROUTER()).getUSDVAmount(amount); // Critical pricing functionality
        _mint(_member, _convertAmount);
    }

    // Redeem to VADER
    function redeem(uint256 amount) external returns (uint256) {
        return redeemForMember(msg.sender, amount);
    }

    // Contracts to redeem for members
    function redeemForMember(address member, uint256 amount) public returns (uint256 redeemAmount) {
        _transfer(msg.sender, VADER, amount); // Move funds
        redeemAmount = iVADER(VADER).redeemToMember(member); // Ask VADER to redeem
        lastBlock[tx.origin] = block.number; // Must record block AFTER the tx
    }

    //============================== ASSETS ================================//

    // @title Deposit tokens into this contract
    // @dev Assumes `token` is trusted and supports
    function getFunds(address token, uint256 amount) internal {
        if (token == address(this)) {
            _transfer(msg.sender, address(this), amount);
        } else {
            require(iERC20(token).transferFrom(msg.sender, address(this), amount)); // safeErc20 not needed; token trusted
        }
    }

    //============================== HELPERS ================================//

    function DAO() internal view returns (address) {
        return iVADER(VADER).DAO();
    }
    function ROUTER() internal view returns (address) {
        return iDAO(iVADER(VADER).DAO()).ROUTER();
    }
}
