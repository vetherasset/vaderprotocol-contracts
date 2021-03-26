// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVAULT{
    function pullIncentives(uint, uint) external;
    function getAnchorPrice() external returns (uint);
    function getUSDVAmount(uint) external view returns (uint);
    function getVDRAmount(uint) external view returns (uint);
}