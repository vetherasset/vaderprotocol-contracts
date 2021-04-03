// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iUSDV {
    function lastBlock(address) external returns (uint);
    function ROUTER() external returns (address);
    function convertToUSDV(uint) external returns(uint);
    function convertToUSDVForMember(address, uint) external returns(uint);
    function redeemToVADER(uint) external returns(uint);
    function redeemToVADERForMember(address, uint) external returns(uint);
}