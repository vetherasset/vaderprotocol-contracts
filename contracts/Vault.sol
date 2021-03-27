// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iUTILS.sol";

    //======================================VADER=========================================//
contract Vault {
    using SafeMath for uint256;

    // Parameters
    uint256 one = 10**18;
    uint256 public reserveVADER;
    uint256 public reserveVSD;
    uint256 public rewardReductionFactor;
    uint256 public timeForFullProtection;
    
    address public VADER;
    address public VSD;
    address public UTILS;
    address public DAO;
    address[] public arrayAnchors;

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

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor(address _vader, address _usdv, address _utils) public {
        VADER = _vader;
        VSD = _usdv;
        UTILS = _utils;
        DAO = msg.sender;
        rewardReductionFactor = 100;
        timeForFullProtection = 8640000; //100 days
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, uint256 inputBase, address token, uint256 inputToken) public returns(uint liquidityUnits){
        address member = msg.sender;
        require(token != VSD);
        uint _actualInputBase;
        if(base == VADER){
            if(!isAnchor(token)){
                _isAnchor[token] = true;
            }
            _actualInputBase = getToken(VADER, inputBase);
        } else if (base == VSD) {
            if(!isAsset(token)){
                _isAsset[token] = true;
            }
            _actualInputBase = getToken(VSD, inputBase);
        }
        uint _actualInputToken = getToken(token, inputToken);
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
        address member = msg.sender;
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
        if(base == VADER){
            reserveVADER = reserveVADER.sub(_protection);
            iERC20(VADER).transfer(member, outputBase);
        } else {
            reserveVSD = reserveVSD.sub(_protection);
            iERC20(VSD).transfer(member, outputBase);
        }
        iERC20(token).transfer(member, outputToken);
        emit RemoveLiquidity(member, base, outputBase, token, outputToken, _units, mapToken_Units[token]);
        return (outputBase, outputToken);
    }

    //=====================================ANCHORS==========================================//
     
    function listAnchor(address anchor) public {
        require(arrayAnchors.length <= 5);
        arrayAnchors.push(anchor);
    }

    function replaceAnchor(address oldAnchor, address newAnchor) public {
        // if baseAmount is greater than old base amount
        // if price newAnchor <2%
        // if price oldAnchor >5%
        // list/delist, add to arrayAnchors
    }

    // price of 1 VADER in USD
    function getAnchorPrice() public view returns (uint anchorPrice){
        // get median of arrayAnchors
        return one;
    }

    // returns the correct amount of Vader for an input of VSD
    function getVADERAmount(uint VSDAmount) public view returns (uint vaderAmount){
        uint _price = getAnchorPrice();
        return (_price.mul(VSDAmount)).div(one);
    }

    // returns the correct amount of Vader for an input of VSD
    function getVSDAmount(uint vaderAmount) public view returns (uint VSDAmount){
        uint _price = getAnchorPrice();
        return (vaderAmount.mul(one)).div(_price);
    }

    
    //=======================================SWAP===========================================//
    
    function swap(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        uint _actualInputAmount = getToken(inputToken, inputAmount);
        if(inputToken == VADER){
            outputAmount = swapFromVADER(inputToken, _actualInputAmount, outputToken);
        } else if (inputToken == VSD) {
            outputAmount = swapFromVSD(_actualInputAmount, outputToken);
        } else if (isAsset(inputToken)) {
            outputAmount = swapFromAsset(inputToken, _actualInputAmount, outputToken);
        } else if (isAnchor(inputToken)) {
            outputAmount = swapFromAnchor(inputToken, _actualInputAmount, outputToken);
        } else {}
        iERC20(outputToken).transfer(msg.sender, outputAmount);
    }

    function swapFromVADER(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // VADER -> VSD
        // VADER -> VSD -> Asset
        // VADER -> Anchor
        if (outputToken == VSD) {
            outputAmount = swapToVSD(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVSD(inputToken, inputAmount);
            outputAmount = swapToAsset(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            outputAmount = swapToAnchor(outputToken, inputAmount);
        } else {}
    }
    function swapFromVSD(uint inputAmount, address outputToken) public returns (uint outputAmount){
        // VSD -> VADER
        // VSD -> Asset
        // VSD -> VADER -> Anchor
        if (outputToken == VADER) {
            outputAmount = swapToAsset(outputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            outputAmount = swapToAsset(outputToken, inputAmount);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount = swapToAsset(VADER, inputAmount);
            outputAmount = swapToAnchor(outputToken, _outputAmount);
        } else {}
    }
    function swapFromAsset(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // Asset -> VSD
        // Asset -> VSD -> VADER
        // Asset -> VSD -> VADER -> Anchor
        if (outputToken == VSD) {
            outputAmount = swapToVSD(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVSD(inputToken, inputAmount);
            outputAmount = swapToVADER(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount1 = swapToVSD(inputToken, inputAmount);
            uint _outputAmount2 = swapToAsset(VADER, _outputAmount1);
            outputAmount = swapToAnchor(outputToken, _outputAmount2);
        } else {}
    }
    function swapFromAnchor(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // Anchor -> VADER
        // Anchor -> VADER -> VSD
        // Anchor -> VADER -> VSD -> Asset
        if (outputToken == VSD) {
            outputAmount = swapToVADER(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVADER(inputToken, inputAmount);
            outputAmount = swapToVSD(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount1 = swapToVADER(inputToken, inputAmount);
            uint _outputAmount2 = swapToVSD(VADER, _outputAmount1);
            outputAmount = swapToAsset(outputToken, _outputAmount2);
        } else {}
    }

    function swapToVSD(address inputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        mapToken_tokenAmount[inputToken] = mapToken_tokenAmount[inputToken].add(inputAmount);
        mapToken_baseAmount[inputToken] = mapToken_baseAmount[inputToken].sub(outputAmount).add(getRewardShare(inputToken));
        return outputAmount;
    }
    function swapToAsset(address outputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        mapToken_baseAmount[outputToken] = mapToken_baseAmount[outputToken].add(inputAmount).add(getRewardShare(outputToken));
        mapToken_tokenAmount[outputToken] = mapToken_tokenAmount[outputToken].sub(outputAmount);
        return outputAmount;
    }
    function swapToVADER(address inputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_tokenAmount[inputToken], mapToken_baseAmount[inputToken]);
        mapToken_tokenAmount[inputToken] = mapToken_tokenAmount[inputToken].add(inputAmount);
        mapToken_baseAmount[inputToken] = mapToken_baseAmount[inputToken].sub(outputAmount).add(getRewardShare(inputToken));
        return outputAmount;
    }
    function swapToAnchor(address outputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapToken_baseAmount[outputToken], mapToken_tokenAmount[outputToken]);
        mapToken_baseAmount[outputToken] = mapToken_baseAmount[outputToken].add(inputAmount).add(getRewardShare(outputToken));
        mapToken_tokenAmount[outputToken] = mapToken_tokenAmount[outputToken].sub(outputAmount);
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
        // iERC20(VADER).transferTo(address(this), shareVADER);
        // iERC20(VSD).transferTo(address(this), shareVSD);
        // reserveVADER = reserveVADER.add(shareVADER);
        // reserveVSD = reserveVSD.add(shareVSD);
    }

    //=================================IMPERMANENT LOSS=====================================//
    
    function addDepositData(address member, address token, uint256 amountBase, uint256 amountToken) internal {
        mapMemberToken_depositBase[member][token] = mapMemberToken_depositBase[member][token].add(amountBase);
        mapMemberToken_depositToken[member][token] = mapMemberToken_depositToken[member][token].add(amountToken);
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
        uint _duration = now - mapMemberToken_lastDeposited[member][token];
        if(_duration <= timeForFullProtection) {
            protection = coverage;
        } else {
            protection = (_duration.mul(coverage)).div(timeForFullProtection);
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
    
    function borrow() public {

    }

    function payBack() public {
        
    }

    function purgeMember() public {

    }

    function getInterestPayment() public {
        
    }

    //======================================HELPERS=========================================//

    // Safe transferFrom in case token charges transfer fees
    function getToken(address _token, uint _amount) internal returns(uint safeAmount) {
        if(_token == VADER || _token == VSD){
            safeAmount = _amount;
            iERC20(_token).transferTo(address(this), _amount);
        } else {
            safeAmount = safeTransferFrom(_token, _amount);
        }
    }
    // Safe transferFrom in case token charges transfer fees
    function safeTransferFrom(address _token, uint _amount) internal returns(uint) {
        uint _startBal = iERC20(_token).balanceOf(address(this));
        iERC20(_token).transferFrom(msg.sender, address(this), _amount);
        return iERC20(_token).balanceOf(address(this)).sub(_startBal);
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

}