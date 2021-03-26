// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";

// Token Contract
contract Token2 is iERC20 {

    using SafeMath for uint256;

    // Coin Defaults
    string public override name;                                         // Name of Coin
    string public override symbol;                                       // Symbol of Coin
    uint256 public override decimals  = 18;                              // Decimals
    uint256 public override totalSupply  = 1*10**9 * (10 ** decimals);   // 1,000,000 Total

    // ERC-20 Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Events
    event Approval(address indexed owner, address indexed spender, uint value); // ERC20
    event Transfer(address indexed from, address indexed to, uint256 value);    // ERC20

    // Minting event
    constructor() public{
        _balances[msg.sender] = totalSupply;
        name = "Token2";
        symbol  = "TKN2";
        emit Transfer(address(0), msg.sender, totalSupply);
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
}