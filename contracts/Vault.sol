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
    uint256 public reserveVADER;
    uint256 public reserveVSD;
    uint256 public pooledVADER;
    uint256 public pooledVSD;
    uint256 public rewardReductionFactor;
    uint256 public timeForFullProtection;
    
    address public VADER;
    address public VSD;
    address public UTILS;
    address public ROUTER;
    address public DAO;

    mapping(address => bool) _isMember;
    mapping(address => bool) _isAsset;
    mapping(address => bool) _isAnchor;

    mapping(address => uint256) public mapToken_Units;
    mapping(address => mapping(address => uint256)) public mapTokenMember_Units;
    mapping(address => uint256) public mapToken_baseAmount;
    mapping(address => uint256) public mapToken_tokenAmount;

    mapping(address => mapping(address => uint256)) public mapMemberToken_depositBase;
    mapping(address => mapping(address => uint256)) public mapMemberToken_depositToken;
    mapping(address => mapping(address => uint256)) public mapMemberToken_lastDeposited;

    // Events
    event AddLiquidity(address indexed member, address indexed base, uint256 baseAmount, address indexed token, uint256 tokenAmount, uint256 liquidityUnits);
    event RemoveLiquidity(address indexed member, address indexed base, uint256 baseAmount, address indexed token, uint256 tokenAmount, uint256 liquidityUnits, uint256 totalUnits);
    event Swap(address indexed member, address indexed inputToken, uint256 inputAmount, address indexed outputToken, uint256 outputAmount, uint256 swapFee, uint256 poolReward);

    //=====================================CREATION=========================================//
    // Constructor
    constructor(address _vader, address _usdv, address _utils, address _router) public {
        VADER = _vader;
        VSD = _usdv;
        UTILS = _utils;
        DAO = msg.sender;
        ROUTER = _router;
        rewardReductionFactor = 1;
        timeForFullProtection = 100;//8640000; //100 days
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, address token, address member) public returns(uint liquidityUnits){
        require(token != VSD);
        uint _actualInputBase;
        if(base == VADER){
            if(!isAnchor(token)){
                _isAnchor[token] = true;
            }
            _actualInputBase = getAddedAmount(VADER, token);
            pooledVADER = pooledVADER.add(_actualInputBase);
        } else if (base == VSD) {
            if(!isAsset(token)){
                _isAsset[token] = true;
            }
            _actualInputBase = getAddedAmount(VSD, token);
            pooledVSD = pooledVSD.add(_actualInputBase);
        }
        uint _actualInputToken = getAddedAmount(token, token);
        liquidityUnits = iUTILS(UTILS).calcLiquidityUnits(_actualInputBase, mapToken_baseAmount[token], _actualInputToken, mapToken_tokenAmount[token], mapToken_Units[token]);
        mapTokenMember_Units[token][member] = mapTokenMember_Units[token][member].add(liquidityUnits);
        mapToken_Units[token] = mapToken_Units[token].add(liquidityUnits);
        mapToken_baseAmount[token] = mapToken_baseAmount[token].add(_actualInputBase);
        mapToken_tokenAmount[token] = mapToken_tokenAmount[token].add(_actualInputToken); 
        addDepositData(member, token, _actualInputBase, _actualInputToken);      
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
        require(base == VSD || base == VADER);
        uint _units = iUTILS(UTILS).calcPart(basisPoints, mapTokenMember_Units[token][member]);
        outputBase = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_baseAmount[token]);
        outputToken = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_tokenAmount[token]);
        mapToken_Units[token] = mapToken_Units[token].sub(_units);
        mapTokenMember_Units[token][member] = mapTokenMember_Units[token][member].sub(_units);
        mapToken_baseAmount[token] = mapToken_baseAmount[token].sub(outputBase);
        mapToken_tokenAmount[token] = mapToken_tokenAmount[token].sub(outputToken);
        uint _protection = getILProtection(member, base, token, basisPoints);
        outputBase = outputBase.add(_protection);
        removeDepositData(member, token, outputBase, outputToken); 
        emit RemoveLiquidity(member, base, outputBase, token, outputToken, _units, mapToken_Units[token]);
        transferOut(base, outputBase, member);
        transferOut(token, outputToken, member);
        return (outputBase, outputToken);
    }
    
    //=======================================SWAP===========================================//
    function swap(address inputToken, address outputToken, address member) public returns (uint outputAmount){
        uint _actualInput;
        if(inputToken == VADER){
            _actualInput = getAddedAmount(VADER, inputToken);
            outputAmount = swapFromVADER(_actualInput, outputToken, member);
        } else if (inputToken == VSD) {
            _actualInput = getAddedAmount(VSD, inputToken);
            outputAmount = swapFromVSD(_actualInput, outputToken, member);
        } else if (isAsset(inputToken)) {
            _actualInput = getAddedAmount(inputToken, inputToken);
            outputAmount = swapFromAsset(inputToken, _actualInput, outputToken, member);
        } else if (isAnchor(inputToken)) {
            _actualInput = getAddedAmount(inputToken, inputToken);
            outputAmount = swapFromAnchor(inputToken, _actualInput, outputToken, member);
        }
        transferOut(outputToken, outputAmount, member);
    }
    
    function swapFromVADER(uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        // VADER -> VSD
        // VADER -> VSD -> Asset
        // VADER -> Anchor
        if (outputToken == VSD) {
            outputAmount = swapToVSD(inputAmount, VADER, member);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVSD(inputAmount, VADER, member);
            outputAmount = swapToAsset(_outputAmount, outputToken, member);
        } else if (isAnchor(outputToken)) {
            outputAmount = swapToAnchor(inputAmount, outputToken, member);
        } else {}
    }
    function swapFromVSD(uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        // VSD -> VADER
        // VSD -> Asset
        // VSD -> VADER -> Anchor
        if (outputToken == VADER) {
            outputAmount = swapToAsset(inputAmount, outputToken, member);
        } else if (isAsset(outputToken)) {
            outputAmount = swapToAsset(inputAmount, outputToken, member);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount = swapToAsset(inputAmount, VADER, member);
            outputAmount = swapToAnchor(_outputAmount, outputToken, member);
        } else {}
    }
    function swapFromAsset(address inputToken, uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        // Asset -> VSD
        // Asset -> VSD -> VADER
        // Asset -> VSD -> VADER -> Anchor
        // Asset -> VSD -> Asset
        if (outputToken == VSD) {
            outputAmount = swapToVSD(inputAmount, inputToken, member);
        } else if (outputToken == VADER) {
            uint _outputAmount = swapToVSD(inputAmount, inputToken, member);
            outputAmount = swapToVADER(_outputAmount, outputToken, member);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount1 = swapToVSD(inputAmount, inputToken, member);
            uint _outputAmount2 = swapToAsset(_outputAmount1, VADER, member);
            outputAmount = swapToAnchor(_outputAmount2, outputToken, member);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVSD(inputAmount, inputToken, member);
            outputAmount = swapToAsset(_outputAmount, outputToken, member);
        }
    }
    function swapFromAnchor(address inputToken, uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        // Anchor -> VADER
        // Anchor -> VADER -> VSD
        // Anchor -> VADER -> VSD -> Asset
        // Anchor -> VADER -> Anchor
        if (outputToken == VADER) {
            outputAmount = swapToVADER(inputAmount, inputToken, member);
        } else if (outputToken == VSD) {
            uint _outputAmount = swapToVADER(inputAmount, inputToken, member);
            outputAmount = swapToVSD(_outputAmount, outputToken, member);
        } else if (isAsset(outputToken)) {
            uint _outputAmount1 = swapToVADER(inputAmount, inputToken, member);
            uint _outputAmount2 = swapToVSD(_outputAmount1, VADER, member);
            outputAmount = swapToAsset(_outputAmount2, outputToken, member);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount = swapToVADER(inputAmount, inputToken, member);
            outputAmount = swapToAsset(_outputAmount, outputToken, member);
        }
    }

    function swapToVSD(uint inputAmount, address inputToken, address member) public returns (uint outputAmount) {
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        uint _swapFee = iUTILS(UTILS).calcSwapFee(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        uint _poolReward = getRewardShare(inputToken);
        mapToken_tokenAmount[inputToken] = mapToken_tokenAmount[inputToken].add(inputAmount);
        mapToken_baseAmount[inputToken] = mapToken_baseAmount[inputToken].sub(outputAmount).add(_poolReward);
        emit Swap(member, inputToken, inputAmount, VSD, outputAmount, _swapFee, _poolReward);
        return outputAmount;
    }
    function swapToAsset(uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        uint _swapFee = iUTILS(UTILS).calcSwapFee(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        uint _poolReward = getRewardShare(outputToken);
        mapToken_baseAmount[outputToken] = mapToken_baseAmount[outputToken].add(inputAmount).add(_poolReward);
        mapToken_tokenAmount[outputToken] = mapToken_tokenAmount[outputToken].sub(outputAmount);
        emit Swap(member, VSD, inputAmount, outputToken, outputAmount, _swapFee, _poolReward);
        return outputAmount;
    }
    function swapToVADER(uint inputAmount, address inputToken, address member) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        uint _swapFee = iUTILS(UTILS).calcSwapFee(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        uint _poolReward = getRewardShare(inputToken);
        mapToken_tokenAmount[inputToken] = mapToken_tokenAmount[inputToken].add(inputAmount);
        mapToken_baseAmount[inputToken] = mapToken_baseAmount[inputToken].sub(outputAmount).add(_poolReward);
        emit Swap(member, inputToken, inputAmount, VADER, outputAmount, _swapFee, _poolReward);
        return outputAmount;
    }
    function swapToAnchor(uint inputAmount, address outputToken, address member) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        uint _swapFee = iUTILS(UTILS).calcSwapFee(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        uint _poolReward = getRewardShare(outputToken);
        mapToken_baseAmount[outputToken] = mapToken_baseAmount[outputToken].add(inputAmount).add(_poolReward);
        mapToken_tokenAmount[outputToken] = mapToken_tokenAmount[outputToken].sub(outputAmount);
        emit Swap(member, VADER, inputAmount, outputToken, outputAmount, _swapFee, _poolReward);
        return outputAmount;
    }

    //====================================INCENTIVES========================================//
    
    function getRewardShare(address token) public view returns (uint rewardShare){
        if (isAsset(token)) {
            uint _baseAmount = mapToken_baseAmount[token];
            uint _totalVSD = iERC20(VSD).balanceOf(address(this)).sub(reserveVSD);
            uint _share = iUTILS(UTILS).calcShare(_baseAmount, _totalVSD, reserveVSD);
            rewardShare = getReducedShare(_share);
        } else if(isAnchor(token)) {
            uint _baseAmount = mapToken_baseAmount[token];
            uint _totalVADER = iERC20(VADER).balanceOf(address(this)).sub(reserveVADER);
            uint _share = iUTILS(UTILS).calcShare(_baseAmount, _totalVADER, reserveVADER);
            rewardShare = getReducedShare(_share);
        }
        return rewardShare;
    }

    function getReducedShare(uint amount) public view returns(uint){
        return iUTILS(UTILS).calcShare(1, rewardReductionFactor, amount);
    }

    function pullIncentives(uint256 shareVADER, uint256 shareVSD) public {
        iERC20(VADER).transferFrom(msg.sender, address(this), shareVADER);
        iERC20(VSD).transferFrom(msg.sender, address(this), shareVSD);
        reserveVADER = reserveVADER.add(shareVADER);
        reserveVSD = reserveVSD.add(shareVSD);
    }

    //=================================IMPERMANENT LOSS=====================================//
    
    function addDepositData(address member, address token, uint256 amountBase, uint256 amountToken) internal {
        mapMemberToken_depositBase[member][token] = mapMemberToken_depositBase[member][token].add(amountBase);
        mapMemberToken_depositToken[member][token] = mapMemberToken_depositToken[member][token].add(amountToken);
        mapMemberToken_lastDeposited[member][token] = now;
    }
    function removeDepositData(address member, address token, uint256 amountBase, uint256 amountToken) internal {
        mapMemberToken_depositBase[member][token] = mapMemberToken_depositBase[member][token].sub(amountBase);
        mapMemberToken_depositToken[member][token] = mapMemberToken_depositToken[member][token].sub(amountToken);
    }

    function getILProtection(address member, address base, address token, uint basisPoints) public view returns(uint protection) {
        protection = getProtection(member, token, basisPoints, getCoverage(member, token));
        if(base == VADER){
            if(protection >= reserveVADER){
                protection = reserveVADER; // In case reserve is running out
            }
        } else {
            if(protection >= reserveVSD){
                protection = reserveVSD; // In case reserve is running out
            }
        }
        return protection;
    }

    function getProtection(address member, address token, uint basisPoints, uint coverage) public view returns(uint protection){
        uint _duration = now.sub(mapMemberToken_lastDeposited[member][token]);
        if(_duration <= timeForFullProtection) {
            protection = iUTILS(UTILS).calcShare(_duration, timeForFullProtection, coverage);
        } else {
            protection = coverage;
        }
        return iUTILS(UTILS).calcPart(basisPoints, protection);
    }
    function getCoverage(address member, address token) public view returns (uint256){
        uint _B0 = mapMemberToken_depositBase[member][token]; uint _T0 = mapMemberToken_depositToken[member][token];
        uint _units = mapTokenMember_Units[token][member];
        uint _B1 = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_baseAmount[token]);
        uint _T1 = iUTILS(UTILS).calcShare(_units, mapToken_Units[token], mapToken_tokenAmount[token]);
        return iUTILS(UTILS).calcCoverage(_B0, _T0, _B1, _T1);
    }
    
    
    //======================================LENDING=========================================//
    

    //======================================HELPERS=========================================//

    // Safe
    function getAddedAmount(address _token, address _pool) internal returns(uint addedAmount) {
        if(_token == VADER && _pool == VADER){
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(mapToken_tokenAmount[_pool]).sub(reserveVADER).sub(pooledVADER);
            pooledVADER = pooledVADER.add(addedAmount);
        } else if(_token == VADER && _pool != VADER){
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(mapToken_baseAmount[_pool]).sub(reserveVADER).sub(pooledVADER);
            pooledVADER = pooledVADER.add(addedAmount);
        } else if(_token == VSD) {
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(mapToken_tokenAmount[_pool]).sub(reserveVSD).sub(pooledVSD);
            pooledVSD = pooledVSD.add(addedAmount);
        } else {
            addedAmount = (iERC20(_token).balanceOf(address(this))).sub(mapToken_tokenAmount[_pool]);
        }
    }
    function transferOut(address _token, uint _amount, address _recipient) internal {
        if(_token == VADER){
            pooledVADER = pooledVADER.sub(_amount);
            iERC20(_token).transfer(_recipient, _amount);
        } else if(_token == VSD) {
            pooledVSD = pooledVSD.sub(_amount);
            iERC20(_token).transfer(_recipient, _amount);
        } else {
            iERC20(_token).transfer(_recipient, _amount);
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
}