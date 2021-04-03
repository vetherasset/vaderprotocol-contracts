// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVADER {
    function UTILS() external view returns (address);
    function secondsPerEra() external view returns (uint);
    function redeem() external returns (uint);
    function redeemForMember(address) external returns (uint);
}