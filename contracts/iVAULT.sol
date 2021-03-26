// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVAULT{
    function pullIncentives() external;
    function getAnchorPrice() external returns (uint);
    function getVUSDAmount(uint) external view returns (uint);
    function getVDRAmount(uint) external view returns (uint);
}