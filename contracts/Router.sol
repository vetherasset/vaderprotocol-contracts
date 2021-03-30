// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;

// Interfaces
import "./iERC20.sol";
import "./SafeMath.sol";
import "./iUTILS.sol";
import "./iVAULT.sol";

import "@nomiclabs/buidler/console.sol";
    //======================================VADER=========================================//
contract Router {
    using SafeMath for uint256;

    // Parameters
    uint256 one = 10**18;
    uint256 _10k = 10000;
    
    address public VADER;
    address public VSD;
    address public UTILS;
    address public DAO;
    address public VAULT;
    address[] public arrayAnchors;
    uint256[] public arrayPrices;

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
    }

    // Can set vault
    function setVault(address _vault) public {
        if(VAULT == address(0)){
            VAULT = _vault;
            iERC20(VADER).approve(VAULT, uint(-1));
            iERC20(VSD).approve(VAULT, uint(-1));
        }
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, uint256 inputBase, address token, uint256 inputToken) public returns(uint){
        moveTokenToVault(base, inputBase);
        moveTokenToVault(token, inputToken);
        return iVAULT(VAULT).addLiquidity(base, token, msg.sender);
    }

    function removeLiquidity(address base, address token, uint basisPoints) public returns (uint, uint) {
        return iVAULT(VAULT).removeLiquidity(base, token, basisPoints);
    }

      //=======================================SWAP===========================================//
    
    function swap(address inputToken, uint inputAmount, address outputToken) public returns (uint outputAmount){
        moveTokenToVault(inputToken, inputAmount);
        outputAmount = iVAULT(VAULT).swap(inputToken, outputToken, msg.sender);
        if(iVAULT(VAULT).isAnchor(inputToken)){
            updateAnchorPrice(inputToken);
        }
        if(iVAULT(VAULT).isAnchor(outputToken)){
            updateAnchorPrice(outputToken);
        }
        return outputAmount;
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) public {
        require(arrayAnchors.length < 5);
        require(iVAULT(VAULT).isAnchor(token));
        arrayAnchors.push(token);
        arrayPrices.push(iUTILS(UTILS).calcValueInBase(token, one));
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) public {
        require(iVAULT(VAULT).isAnchor(newToken), "Not anchor");
        require((iVAULT(VAULT).getBaseAmount(newToken) > iVAULT(VAULT).getBaseAmount(oldToken)), "Not deeper");
        _requirePriceBounds(oldToken, 500, false);                              // if price oldToken >5%
        _requirePriceBounds(newToken, 200, true);                               // if price newToken <2%
        // list/delist, add to arrayAnchors
        for(uint i = 0; i<arrayAnchors.length; i++){
            if(arrayAnchors[i] == oldToken){
                arrayAnchors[i] = newToken;
            }
        }
        updateAnchorPrice(newToken);
    }

    function _requirePriceBounds(address token, uint bound, bool inside) internal view {
        uint _targetPrice = getAnchorPrice();
        uint _testingPrice = iUTILS(UTILS).calcValueInBase(token, one);
        uint _lower = iUTILS(UTILS).calcPart(_10k.sub(bound), _targetPrice);
        uint _upper = (_targetPrice.mul(_10k.add(bound))).div(_10k);
        if(inside){
            require((_testingPrice >= _lower && _testingPrice <= _upper), "Not inside");
        } else {
            require((_testingPrice <= _lower || _testingPrice >= _upper), "Not outside");
        }
    }

    // Anyone to update prices
    function updateAnchorPrice(address token) public {
        for(uint i = 0; i<arrayAnchors.length; i++){
            if(arrayAnchors[i] == token){
                arrayPrices[i] = iUTILS(UTILS).calcValueInBase(arrayAnchors[i], one);
            }
        }
    }

    // Price of 1 VADER in USD
    function getAnchorPrice() public view returns (uint anchorPrice){
        uint[] memory _sortedAnchorFeed = _sortArray(arrayPrices);  // Sort price array
        return _sortedAnchorFeed[2];                                // Return the middle
    }

    // The correct amount of Vader for an input of USDV
    function getVADERAmount(uint VSDAmount) public view returns (uint vaderAmount){
        uint _price = getAnchorPrice();
        return (_price.mul(VSDAmount)).div(one);
    }

    // The correct amount of USDV for an input of VADER
    function getVSDAmount(uint vaderAmount) public view returns (uint VSDAmount){
        uint _price = getAnchorPrice();
        return (vaderAmount.mul(one)).div(_price);
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
    function moveTokenToVault(address _token, uint _amount) internal {
        if(_token == VADER || _token == VSD){
            iERC20(_token).transferTo(VAULT, _amount);
        } else {
            iERC20(_token).transferFrom(msg.sender, VAULT, _amount);
        }
    }

    function _sortArray(uint[] memory array) internal pure returns (uint[] memory){
        uint l = array.length;
        for(uint i = 0; i < l; i++){
            for(uint j = i+1; j < l; j++){
                if(array[i] > array[j]){
                    uint temp = array[i];
                    array[i] = array[j];
                    array[j] = temp;
                }
            }
        }
        return array;
    }
}