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
    
    address public VADER;
    address public VUSD;
    address public UTILS;
    address public DAO;
    address[] public arrayAnchors;

    mapping(address => bool) _isMember;
    mapping(address => bool) _isAsset;
    mapping(address => bool) _isAnchor;

    mapping(address => uint256) public mapAsset_Units;
    mapping(address => mapping(address => uint256)) public mapAssetMember_Units;
    mapping(address => uint256) public mapAsset_baseAmount;
    mapping(address => uint256) public mapAsset_tokenAmount;

    mapping(address => uint256) public mapAnchor_Units;
    mapping(address => mapping(address => uint256)) public mapAnchorMember_Units;
    mapping(address => uint256) public mapAnchor_baseAmount;
    mapping(address => uint256) public mapAnchor_tokenAmount;

    // Events
    event AddLiquidityAsset(address indexed token, address indexed member, uint256 baseAmount, uint256 tokenAmount, uint256 liquidityUnits);
    event AddLiquidityAnchor(address indexed token, address indexed member, uint256 baseAmount, uint256 tokenAmount, uint256 liquidityUnits, uint256 totalUnits);
    event RemoveLiquidityAsset(address indexed token, address indexed member, uint256 baseAmount, uint256 tokenAmount, uint256 liquidityUnits, uint256 totalUnits);
    event RemoveLiquidityAnchor(address indexed token, address indexed member, uint256 baseAmount, uint256 tokenAmount, uint256 liquidityUnits, uint256 totalUnits);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO, "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor(address _vader, address _vusd, address _utils) public {
        VADER = _vader;
        VUSD = _vusd;
        UTILS = _utils;
        DAO = msg.sender;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidityAsset(uint256 inputBase, address token, uint256 inputToken) public returns(uint liquidityUnits){
        address member = msg.sender;
        if(!isAsset(token)){
            _isAsset[token] = true;
        }
        uint _actualInputBase = getToken(VUSD, inputBase);
        uint _actualInputToken = getToken(token, inputToken);
        liquidityUnits = iUTILS(UTILS).calcLiquidityUnits(_actualInputBase, mapAsset_baseAmount[token], _actualInputToken, mapAsset_tokenAmount[token], mapAsset_Units[token]);
        mapAssetMember_Units[token][member] = mapAssetMember_Units[token][member].add(liquidityUnits);
        mapAsset_Units[token] = mapAsset_Units[token].add(liquidityUnits);
        mapAsset_baseAmount[token] = mapAsset_baseAmount[token].add(_actualInputBase);
        mapAsset_tokenAmount[token] = mapAsset_tokenAmount[token].add(_actualInputToken);        emit AddLiquidityAsset(token, member, _actualInputBase, _actualInputToken, liquidityUnits);
        return liquidityUnits;
    }

    function addLiquidityAnchor(uint256 inputBase, address token, uint256 inputToken) public returns(uint liquidityUnits){
        address member = msg.sender;
        if(!isAnchor(token)){
            _isAnchor[token] = true;
        }
        uint _actualInputBase = getToken(VADER, inputBase);
        uint _actualInputToken = getToken(token, inputToken);
        liquidityUnits = iUTILS(UTILS).calcLiquidityUnits(_actualInputBase, mapAnchor_baseAmount[token], _actualInputToken, mapAnchor_tokenAmount[token], mapAnchor_Units[token]);
        mapAnchorMember_Units[token][member] = mapAnchorMember_Units[token][member].add(liquidityUnits);
        mapAnchor_Units[token] = mapAnchor_Units[token].add(liquidityUnits);
        mapAnchor_baseAmount[token] = mapAnchor_baseAmount[token].add(_actualInputBase);
        mapAnchor_tokenAmount[token] = mapAnchor_tokenAmount[token].add(_actualInputToken);
        emit AddLiquidityAnchor(token, member, _actualInputBase, _actualInputToken, liquidityUnits, mapAnchor_Units[token]);
        return liquidityUnits;
    }

    function removeLiquidityAsset(address token, uint basisPoints) public returns (uint outputBase, uint outputToken) {
        address member = msg.sender;
        uint _units = iUTILS(UTILS).calcPart(basisPoints, mapAssetMember_Units[token][member]);
        outputBase = iUTILS(UTILS).calcShare(_units, mapAsset_Units[token], mapAsset_baseAmount[token]);
        outputToken = iUTILS(UTILS).calcShare(_units, mapAsset_Units[token], mapAsset_tokenAmount[token]);
        mapAsset_Units[token] = mapAsset_Units[token].sub(_units);
        mapAssetMember_Units[token][member] = mapAssetMember_Units[token][member].sub(_units);
        mapAsset_baseAmount[token] = mapAsset_baseAmount[token].sub(outputBase);
        mapAsset_tokenAmount[token] = mapAsset_tokenAmount[token].sub(outputToken);
        iERC20(VUSD).transfer(member, outputBase);
        iERC20(token).transfer(member, outputToken);
        emit RemoveLiquidityAsset(token, member, outputBase, outputToken, _units, mapAsset_Units[token]);
        return (outputBase, outputToken);
    }

    function removeLiquidityAnchor(address token, uint basisPoints) public returns (uint outputBase, uint outputToken) {
        address member = msg.sender;
        uint _units = iUTILS(UTILS).calcPart(basisPoints, mapAnchorMember_Units[token][member]);
        outputBase = iUTILS(UTILS).calcShare(_units, mapAnchor_Units[token], mapAnchor_baseAmount[token]);
        outputToken = iUTILS(UTILS).calcShare(_units, mapAnchor_Units[token], mapAnchor_tokenAmount[token]);
        mapAnchor_Units[token] = mapAnchor_Units[token].sub(_units);
        mapAnchorMember_Units[token][member] = mapAnchorMember_Units[token][member].sub(_units);
        mapAnchor_baseAmount[token] = mapAnchor_baseAmount[token].sub(outputBase);
        mapAnchor_tokenAmount[token] = mapAnchor_tokenAmount[token].sub(outputToken);
        iERC20(VADER).transfer(member, outputBase);
        iERC20(token).transfer(member, outputToken);
        emit RemoveLiquidityAnchor(token, member, outputBase, outputToken, _units, mapAnchor_Units[token]);
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

    // returns the correct amount of Vader for an input of vUSD
    function getVDRAmount(uint vUSDAmount) public view returns (uint vaderAmount){
        uint _price = getAnchorPrice();
        return (_price.mul(vUSDAmount)).div(one);
    }

    // returns the correct amount of Vader for an input of vUSD
    function getVUSDAmount(uint vaderAmount) public view returns (uint vUSDAmount){
        uint _price = getAnchorPrice();
        return (vaderAmount.mul(one)).div(_price);
    }

    
    //=======================================SWAP===========================================//
    
    function swap(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        uint _actualInputAmount = getToken(inputToken, inputAmount);
        if(inputToken == VADER){
            outputAmount = swapFromVDR(inputToken, _actualInputAmount, outputToken);
        } else if (inputToken == VUSD) {
            outputAmount = swapFromVUSD(inputToken, _actualInputAmount, outputToken);
        } else if (isAsset(inputToken)) {
            outputAmount = swapFromAsset(inputToken, _actualInputAmount, outputToken);
        } else if (isAnchor(inputToken)) {
            outputAmount = swapFromAnchor(inputToken, _actualInputAmount, outputToken);
        } else {}
        iERC20(outputToken).transfer(msg.sender, outputAmount);
    }

    function swapFromVDR(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // VDR -> vUSD
        // VDR -> vUSD -> Asset
        // VDR -> Anchor
        if (outputToken == VUSD) {
            outputAmount = swapToVUSD(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVUSD(inputToken, inputAmount);
            outputAmount = swapToAsset(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            outputAmount = swapToAnchor(outputToken, inputAmount);
        } else {}
    }
    function swapFromVUSD(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // vUSD -> VDR
        // vUSD -> Asset
        // vUSD -> VDR -> Anchor
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
        // Asset -> vUSD
        // Asset -> vUSD -> VDR
        // Asset -> vUSD -> VDR -> Anchor
        if (outputToken == VUSD) {
            outputAmount = swapToVUSD(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVUSD(inputToken, inputAmount);
            outputAmount = swapToVADER(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount1 = swapToVUSD(inputToken, inputAmount);
            uint _outputAmount2 = swapToAsset(VADER, _outputAmount1);
            outputAmount = swapToAnchor(outputToken, _outputAmount2);
        } else {}
    }
    function swapFromAnchor(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        // Anchor -> VDR
        // Anchor -> VDR -> vUSD
        // Anchor -> VDR -> vUSD -> Asset
        if (outputToken == VUSD) {
            outputAmount = swapToVADER(inputToken, inputAmount);
        } else if (isAsset(outputToken)) {
            uint _outputAmount = swapToVADER(inputToken, inputAmount);
            outputAmount = swapToVUSD(outputToken, _outputAmount);
        } else if (isAnchor(outputToken)) {
            uint _outputAmount1 = swapToVADER(inputToken, inputAmount);
            uint _outputAmount2 = swapToVUSD(VADER, _outputAmount1);
            outputAmount = swapToAsset(outputToken, _outputAmount2);
        } else {}
    }

    function swapToVUSD(address inputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapAsset_tokenAmount[inputToken], mapAsset_baseAmount[inputToken]);
        mapAsset_tokenAmount[inputToken] = mapAsset_tokenAmount[inputToken].add(inputAmount);
        mapAsset_baseAmount[inputToken] = mapAsset_baseAmount[inputToken].sub(outputAmount);
        return outputAmount;
    }
    function swapToAsset(address outputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapAsset_baseAmount[outputToken], mapAsset_tokenAmount[outputToken]);
        mapAsset_baseAmount[outputToken] = mapAsset_baseAmount[outputToken].add(inputAmount);
        mapAsset_tokenAmount[outputToken] = mapAsset_tokenAmount[outputToken].sub(outputAmount);
        return outputAmount;
    }
    function swapToVADER(address inputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapAnchor_tokenAmount[inputToken], mapAnchor_baseAmount[inputToken]);
        mapAnchor_tokenAmount[inputToken] = mapAnchor_tokenAmount[inputToken].add(inputAmount);
        mapAnchor_baseAmount[inputToken] = mapAnchor_baseAmount[inputToken].sub(outputAmount);
        return outputAmount;
    }
    function swapToAnchor(address outputToken, uint inputAmount) public returns (uint outputAmount){
        outputAmount = iUTILS(UTILS).calcSwapOutput(inputAmount, mapAnchor_baseAmount[outputToken], mapAnchor_tokenAmount[outputToken]);
        mapAnchor_baseAmount[outputToken] = mapAnchor_baseAmount[outputToken].add(inputAmount);
        mapAnchor_tokenAmount[outputToken] = mapAnchor_tokenAmount[outputToken].sub(outputAmount);
        return outputAmount;
    }

    //====================================INCENTIVES========================================//
    
    function getRewardShare() public {

    }

    function pullIncentives() public {
        
    }

    //=================================IMPERMANENT LOSS=====================================//
    
    function getILCoverage() public {

    }

    function getILProtection() public {
        
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
        if(_token == VADER || _token == VUSD){
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