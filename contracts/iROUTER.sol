// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iROUTER {
    function getAnchorPrice() external returns (uint);
    function getVSDAmount(uint) external view returns (uint);
    function getVADERAmount(uint) external view returns (uint);
    function pullIncentives(uint, uint) external;
}