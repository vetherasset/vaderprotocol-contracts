// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface iROUTER {
    function getAnchorPrice() external returns (uint);
    function getUSDVAmount(uint) external view returns (uint);
    function getVADERAmount(uint) external view returns (uint);
    function pullIncentives(uint, uint) external;
}