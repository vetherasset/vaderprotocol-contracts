// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iVADER {
    function UTILS() external view returns (address);
    function DAO() external view returns (address);
    function emitting() external view returns (bool);
    function secondsPerEra() external view returns (uint);
    function redeem() external returns (uint);
    function redeemToMember(address) external returns (uint);
    function changeUTILS(address) external;
    function setRewardAddress(address) external;
}