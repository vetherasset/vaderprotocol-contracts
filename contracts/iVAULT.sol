// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVAULT{
    function addLiquidity(address, address, address) external returns(uint);
    function removeLiquidity(address, address, uint) external returns (uint, uint);
    function swap(address, address, address) external returns (uint);
    function pullIncentives(uint, uint) external;
    function getAnchorPrice() external returns (uint);
    function getVSDAmount(uint) external view returns (uint);
    function getVADERAmount(uint) external view returns (uint);
    function isMember(address) external view returns(bool);
    function isAsset(address) external view returns(bool);
    function isAnchor(address) external view returns(bool);
    function getPoolAmounts(address) external view returns(uint, uint);
    function getBaseAmount(address) external view returns(uint);
    function getTokenAmount(address) external view returns(uint);
}