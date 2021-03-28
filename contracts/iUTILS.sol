// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iUTILS {
    function calcPart(uint bp, uint total) external pure returns (uint part);
    function calcShare(uint part, uint total, uint amount) external pure returns (uint share);
    function calcSwapOutput(uint x, uint X, uint Y) external pure returns (uint output);
    function calcSwapFee(uint x, uint X, uint Y) external pure returns (uint output);
    function calcLiquidityUnits(uint b, uint B, uint t, uint T, uint P) external view returns (uint units);
    function getSlipAdustment(uint b, uint B, uint t, uint T) external view returns (uint slipAdjustment);
    function calcAsymmetricShare(uint u, uint U, uint A) external pure returns (uint share);
    function calcCoverage(uint _B0, uint _T0, uint _B1, uint _T1) external pure returns(uint coverage);
}