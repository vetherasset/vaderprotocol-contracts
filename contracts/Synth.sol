// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";

// Synth Contract
contract Synth is iERC20 {
    address public immutable FACTORY;
    address public immutable TOKEN;

    // Coin Defaults
    string public override name;
    string public override symbol;
    uint256 public immutable override decimals = 18;
    uint256 public override totalSupply;

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    modifier onlyFACTORY() {
        require(msg.sender == FACTORY, "!FACTORY");
        _;
    }

    // Minting event
    constructor(address _token) {
        TOKEN = _token;
        FACTORY = msg.sender;
        string memory synthName = " - vSynth";
        string memory synthSymbol = ".v";
        name = string(abi.encodePacked(iERC20(_token).name(), synthName));
        symbol = string(abi.encodePacked(iERC20(_token).symbol(), synthSymbol));
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
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        // Unlimited approval (saves an SSTORE)
        if (_allowances[sender][msg.sender] < type(uint256).max) {
            _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        }
        return true;
    }

    // TransferTo function
    // Risks: User can be phished, or tx.origin may be deprecated, optionality should exist in the system.
    function transferTo(address recipient, uint256 amount) public virtual override returns (bool) {
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
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    // Only FACTORY can mint
    function mint(address account, uint256 amount) external virtual onlyFACTORY {
        require(account != address(0), "recipient");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    // Burn supply
    function burn(uint256 amount) public virtual override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public virtual override {
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
}
