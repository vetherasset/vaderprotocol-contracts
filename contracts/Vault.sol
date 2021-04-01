// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iUTILS.sol";
import "@nomiclabs/buidler/console.sol";
    //======================================VADER=========================================//
contract Vault {
    using SafeMath for uint256;

    // Parameters
    bool private inited;
    uint256 public pooledVADER;
    uint256 public pooledVSD;
    
    address public VADER;
    address public USDV;
    address public UTILS;
    address public ROUTER;

    mapping(address => bool) _isMember;
    mapping(address => bool) _isAsset;
    mapping(address => bool) _isAnchor;

    mapping(address => uint256) public mapToken_Units;
    mapping(address => mapping(address => uint256)) public mapTokenMember_Units;
    mapping(address => uint256) public mapToken_baseAmount;
    mapping(address => uint256) public mapToken_tokenAmount;

    // Events
    event AddLiquidity(address indexed member, address indexed base, uint256 baseAmount, address indexed token, uint256 tokenAmount, uint256 liquidityUnits);
    event RemoveLiquidity(address indexed member, address indexed base, uint256 baseAmount, address indexed token, uint256 tokenAmount, uint256 liquidityUnits, uint256 totalUnits);
    event Swap(address indexed member, address indexed inputToken, uint256 inputAmount, address indexed outputToken, uint256 outputAmount, uint256 swapFee);
    event Sync(address indexed token, address indexed pool, uint256 addedAmount);

    //=====================================CREATION=========================================//
    // Constructor
    constructor() public {}
    // Init
    function init(address _vader, address _usdv, address _utils, address _router) public {
        require(inited == false);
        VADER = _vader;
        USDV = _usdv;
        UTILS = _utils;
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
        liquidityUnits = iUTILS(UTILS).calcLiquidityUnits(_actualInputBase, mapToken_baseAmount[token], _actualInputToken, mapToken_tokenAmount[token], mapToken_Units[token]);
        mapTokenMember_Units[token][member] = mapTokenMember_Units[token][member].add(liquidityUnits);
        mapToken_Units[token] = mapToken_Units[token].add(liquidityUnits);
        mapToken_baseAmount[token] = mapToken_baseAmount[token].add(_actualInputBase);
        mapToken_tokenAmount[token] = mapToken_tokenAmount[token].add(_actualInputToken);      
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
        uint _units = iUTILS(UTILS).calcPart(basisPoints, mapTokenMember_Units[token][member]);
        outputBase = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_baseAmount[token]);
        outputToken = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_tokenAmount[token]);
        mapToken_Units[token] = mapToken_Units[token].sub(_units);
        mapTokenMember_Units[token][member] = mapTokenMember_Units[token][member].sub(_units);
        mapToken_baseAmount[token] = mapToken_baseAmount[token].sub(outputBase);
        mapToken_tokenAmount[token] = mapToken_tokenAmount[token].sub(outputToken);
        emit RemoveLiquidity(member, base, outputBase, token, outputToken, _units, mapToken_Units[token]);
        transferOut(base, outputBase, member);
        transferOut(token, outputToken, member);
        return (outputBase, outputToken);
    }
    
    //=======================================SWAP===========================================//
    function sync(address token, address pool) public {
        uint _actualInput = getAddedAmount(token, pool);
        if (token == VADER || token == USDV){
            mapToken_baseAmount[token] = mapToken_baseAmount[token].add(_actualInput);
        } else {
            mapToken_tokenAmount[token] = mapToken_tokenAmount[token].add(_actualInput);
        }
        emit Sync(token, pool, _actualInput);
    }
    
    function swap(address base, address token, address member, bool toBase) public returns (uint outputAmount){
        if(toBase){
            uint _actualInput = getAddedAmount(token, token);
            outputAmount = iUTILS(UTILS).calcSwapOutput(_actualInput, mapToken_tokenAmount[token], mapToken_baseAmount[token]);
            uint _swapFee = iUTILS(UTILS).calcSwapFee(_actualInput, mapToken_tokenAmount[token], mapToken_baseAmount[token]);
            mapToken_tokenAmount[token] = mapToken_tokenAmount[token].add(_actualInput);
            mapToken_baseAmount[token] = mapToken_baseAmount[token].sub(outputAmount);
            emit Swap(member, token, _actualInput, base, outputAmount, _swapFee);
            transferOut(base, outputAmount, member);
        } else {
            uint _actualInput = getAddedAmount(base, token);
            outputAmount = iUTILS(UTILS).calcSwapOutput(_actualInput, mapToken_baseAmount[token], mapToken_tokenAmount[token]);
            uint _swapFee = iUTILS(UTILS).calcSwapFee(_actualInput, mapToken_baseAmount[token], mapToken_tokenAmount[token]);
            mapToken_baseAmount[token] = mapToken_baseAmount[token].add(_actualInput);
            mapToken_tokenAmount[token] = mapToken_tokenAmount[token].sub(outputAmount);
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
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(pooledVADER);
            pooledVADER = pooledVADER.add(addedAmount);
        } else if(_token == VADER && _pool != VADER){
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(pooledVADER);
            pooledVADER = pooledVADER.add(addedAmount);
        } else if(_token == USDV) {
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(pooledVSD);
            pooledVSD = pooledVSD.add(addedAmount);
        } else {
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(mapToken_tokenAmount[_pool]);
        }
    }
    function transferOut(address _token, uint _amount, address _recipient) internal {
        if(_token == VADER){
            pooledVADER = pooledVADER.sub(_amount);
            if(_recipient != address(this)){
                iERC20(_token).transfer(_recipient, _amount);
            }
        } else if(_token == USDV) {
            pooledVSD = pooledVSD.sub(_amount);
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
}