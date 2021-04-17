// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface iUSDV {
    function isMature() external view returns (bool);
    function ROUTER() external view returns (address);
    function convert(uint) external returns(uint);
    function convertForMember(address, uint) external returns(uint);
    function redeem(uint) external returns(uint);
    function redeemForMember(address, uint) external returns(uint);
    function totalFunds() external view returns(uint);
    function getMemberDeposit(address) external view returns(uint);
    function grant(address, uint) external;
}