// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface iUSDV {
    function lastBlock(address) external view returns (uint);
    function ROUTER() external view returns (address);
    function convertToUSDV(uint) external returns(uint);
    function convertToUSDVForMember(address, uint) external returns(uint);
    function redeemToVADER(uint) external returns(uint);
    function redeemToVADERForMember(address, uint) external returns(uint);
    function totalFunds() external view returns(uint);
    function getMemberDeposit(address) external view returns(uint);
    function grant(address, uint) external;
}