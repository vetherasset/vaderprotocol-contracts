// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface iUTILS {
    function getFeeOnTransfer(uint, uint) external pure returns (uint);
    function calcPart(uint, uint) external pure returns (uint);
    function calcShare(uint, uint, uint) external pure returns (uint);
    function calcSwapOutput(uint, uint, uint) external pure returns (uint);
    function calcSwapFee(uint, uint, uint) external pure returns (uint);
    function calcSwapSlip(uint, uint) external pure returns (uint);
    function calcLiquidityUnits(uint, uint, uint, uint, uint) external view returns (uint);
    function calcSynthUnits(uint, uint, uint) external view returns (uint);
    function getSlipAdustment(uint, uint, uint, uint) external view returns (uint);
    function calcAsymmetricShare(uint, uint, uint) external pure returns (uint);
    function calcCoverage(uint, uint, uint, uint) external pure returns(uint);
    function calcValueInBase(address, uint) external view returns (uint);
    function calcValueInToken(address, uint) external view returns (uint);
    function calcSwapValueInBase(address token, uint amount) external view returns (uint value);
    function calcSwapValueInToken(address token, uint amount) external view returns (uint value);
}