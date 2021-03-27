// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVADER {
    function nextEraTime() external view returns (uint);
    function secondsPerEra() external view returns (uint);
    function redeem() external returns (uint);
}