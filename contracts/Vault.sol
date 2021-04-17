// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";

    //======================================VADER=========================================//
contract Vault {

    // Parameters
    bool private inited;
    uint public pooledVADER;
    uint public pooledUSDV;
    
    address public VADER;
    address public USDV;
    address public ROUTER;

    mapping(address => bool) _isMember;
    mapping(address => bool) _isAsset;
    mapping(address => bool) _isAnchor;

    mapping(address => uint) public mapToken_Units;
    mapping(address => mapping(address => uint)) public mapTokenMember_Units;
    mapping(address => uint) public mapToken_baseAmount;
    mapping(address => uint) public mapToken_tokenAmount;

    // Events
    event AddLiquidity(address indexed member, address indexed base, uint baseAmount, address indexed token, uint tokenAmount, uint liquidityUnits);
    event RemoveLiquidity(address indexed member, address indexed base, uint baseAmount, address indexed token, uint tokenAmount, uint liquidityUnits, uint totalUnits);
    event Swap(address indexed member, address indexed inputToken, uint inputAmount, address indexed outputToken, uint outputAmount, uint swapFee);
    event Sync(address indexed token, address indexed pool, uint addedAmount);

    //=====================================CREATION=========================================//
    // Constructor
    constructor() {}

    // Init
    function init(address _vader, address _usdv, address _router) public {
        require(!inited);
        require(_vader != address(0));
        require(_usdv != address(0));
        require(_router != address(0));
        VADER = _vader;
        USDV = _usdv;
        ROUTER = _router;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, address token, address member) public returns(uint liquidityUnits){
        require(token != USDV);
        uint _actualInputBase;
        if(base == VADER){
            if(!isAnchor(token)){
                _isAnchor[token] = true;
            }
            _actualInputBase = getAddedAmount(VADER, token);
        } else if (base == USDV) {
            if(!isAsset(token)){
                _isAsset[token] = true;
            }
            _actualInputBase = getAddedAmount(USDV, token);
        }
        uint _actualInputToken = getAddedAmount(token, token);
        liquidityUnits = iUTILS(UTILS()).calcLiquidityUnits(_actualInputBase, mapToken_baseAmount[token], _actualInputToken, mapToken_tokenAmount[token], mapToken_Units[token]);
        mapTokenMember_Units[token][member] += liquidityUnits;
        mapToken_Units[token] += liquidityUnits;
        mapToken_baseAmount[token] += _actualInputBase;
        mapToken_tokenAmount[token] += _actualInputToken;      
        emit AddLiquidity(member, base, _actualInputBase, token, _actualInputToken, liquidityUnits);
        return liquidityUnits;
    }

    function removeLiquidity(address base, address token, uint basisPoints) public returns (uint outputBase, uint outputToken) {
        return _removeLiquidity(base, token, basisPoints, tx.origin);
    }
    function removeLiquidityDirectly(address base, address token, uint basisPoints) public returns (uint outputBase, uint outputToken) {
        return _removeLiquidity(base, token, basisPoints, msg.sender);
    }
    function _removeLiquidity(address base, address token, uint basisPoints, address member) internal returns (uint outputBase, uint outputToken) {
        require(base == USDV || base == VADER);
        uint _units = iUTILS(UTILS()).calcPart(basisPoints, mapTokenMember_Units[token][member]);
        outputBase = iUTILS(UTILS()).calcShare(_units, mapToken_Units[token], mapToken_baseAmount[token]);
        outputToken = iUTILS(UTILS()).calcShare(_units, mapToken_Units[token], mapToken_tokenAmount[token]);
        mapToken_Units[token] -=_units;
        mapTokenMember_Units[token][member] -= _units;
        mapToken_baseAmount[token] -= outputBase;
        mapToken_tokenAmount[token] -= outputToken;
        emit RemoveLiquidity(member, base, outputBase, token, outputToken, _units, mapToken_Units[token]);
        transferOut(base, outputBase, member);
        transferOut(token, outputToken, member);
        return (outputBase, outputToken);
    }
    
    //=======================================SWAP===========================================//
    function sync(address token, address pool) public {
        uint _actualInput = getAddedAmount(token, pool);
        if (token == VADER || token == USDV){
            mapToken_baseAmount[pool] += _actualInput;
        } else {
            mapToken_tokenAmount[pool] += _actualInput;
        }
        emit Sync(token, pool, _actualInput);
    }
    
    function swap(address base, address token, address member, bool toBase) public returns (uint outputAmount){
        if(toBase){
            uint _actualInput = getAddedAmount(token, token);
            outputAmount = iUTILS(UTILS()).calcSwapOutput(_actualInput, mapToken_tokenAmount[token], mapToken_baseAmount[token]);
            uint _swapFee = iUTILS(UTILS()).calcSwapFee(_actualInput, mapToken_tokenAmount[token], mapToken_baseAmount[token]);
            mapToken_tokenAmount[token] += _actualInput;
            mapToken_baseAmount[token] -= outputAmount;
            emit Swap(member, token, _actualInput, base, outputAmount, _swapFee);
            transferOut(base, outputAmount, member);
        } else {
            uint _actualInput = getAddedAmount(base, token);
            outputAmount = iUTILS(UTILS()).calcSwapOutput(_actualInput, mapToken_baseAmount[token], mapToken_tokenAmount[token]);
            uint _swapFee = iUTILS(UTILS()).calcSwapFee(_actualInput, mapToken_baseAmount[token], mapToken_tokenAmount[token]);
            mapToken_baseAmount[token] += _actualInput;
            mapToken_tokenAmount[token] -= outputAmount;
            emit Swap(member, base, _actualInput, token, outputAmount, _swapFee);
            transferOut(token, outputAmount, member);
        }
        return outputAmount;
    }
    
    //======================================LENDING=========================================//
    

    //======================================HELPERS=========================================//

    // Safe
    function getAddedAmount(address _token, address _pool) internal returns(uint addedAmount) {
        if(_token == VADER && _pool == VADER){
            addedAmount = (iERC20(_token).balanceOf(address(this))) - pooledVADER;
            pooledVADER = pooledVADER + addedAmount;
        } else if(_token == VADER && _pool != VADER){
            addedAmount = (iERC20(_token).balanceOf(address(this))) - pooledVADER;
            pooledVADER = pooledVADER + addedAmount;
        } else if(_token == USDV) {
            addedAmount = (iERC20(_token).balanceOf(address(this))) - pooledUSDV;
            pooledUSDV = pooledUSDV + addedAmount;
        } else {
            addedAmount = (iERC20(_token).balanceOf(address(this))) - mapToken_tokenAmount[_pool];
        }
    }
    function transferOut(address _token, uint _amount, address _recipient) internal {
        if(_token == VADER){
            pooledVADER = pooledVADER - _amount;
            if(_recipient != address(this)){
                iERC20(_token).transfer(_recipient, _amount);
            }
        } else if(_token == USDV) {
            pooledUSDV = pooledUSDV - _amount;
            if(_recipient != address(this)){
                iERC20(_token).transfer(_recipient, _amount);
            }
        } else {
            if(_recipient != address(this)){
                iERC20(_token).transfer(_recipient, _amount);
            }
        }
        
    }

    function isMember(address member) public view returns(bool) {
        return _isMember[member];
    }
    function isAsset(address token) public view returns(bool) {
        return _isAsset[token];
    }
    function isAnchor(address token) public view returns(bool) {
        return _isAnchor[token];
    }
    function getPoolAmounts(address token) public view returns(uint, uint) {
        return (getBaseAmount(token), getTokenAmount(token));
    }
    function getBaseAmount(address token) public view returns(uint) {
        return mapToken_baseAmount[token];
    }
    function getTokenAmount(address token) public view returns(uint) {
        return mapToken_tokenAmount[token];
    }
    function getUnits(address token) public view returns(uint) {
        return mapToken_Units[token];
    }
    function getMemberUnits(address token, address member) public view returns(uint) {
        return mapTokenMember_Units[token][member];
    }
    function UTILS() public view returns(address){
        return iVADER(VADER).UTILS();
    }
}
