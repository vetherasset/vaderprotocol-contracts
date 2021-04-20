// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iUTILS {
    function getFeeOnTransfer(uint totalSupply, uint maxSupply) external pure returns (uint);
    function calcValueInBase(address token, uint amount) external view returns (uint);
    function calcValueInToken(address token, uint amount) external view returns (uint);
    function calcValueOfTokenInToken(address token1, uint amount, address token2) external view returns (uint);
    function calcSwapValueInBase(address token, uint amount) external view returns (uint);
    function calcSwapValueInToken(address token, uint amount) external view returns (uint);
    function calcPart(uint bp, uint total) external pure returns (uint);
    function calcShare(uint part, uint total, uint amount) external pure returns (uint);
    function calcSwapOutput(uint x, uint X, uint Y) external pure returns (uint);
    function calcSwapFee(uint x, uint X, uint Y) external pure returns (uint);
    function calcSwapSlip(uint x, uint X) external pure returns (uint);
    function calcLiquidityUnits(uint b, uint B, uint t, uint T, uint P) external view returns (uint);
    function getSlipAdustment(uint b, uint B, uint t, uint T) external view returns (uint);
    function calcSynthUnits(uint b, uint B, uint P) external view returns (uint);
    function calcAsymmetricShare(uint u, uint U, uint A) external pure returns (uint);
    function calcCoverage(uint B0, uint T0, uint B1, uint T1) external pure returns(uint);
    
}