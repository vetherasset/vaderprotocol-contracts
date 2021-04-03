// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.8;
interface iVADER {
    function UTILS() external view returns (address);
    function DAO() external view returns (address);
    function emitting() external view returns (bool);
    function secondsPerEra() external view returns (uint);
    function redeem() external returns (uint);
    function redeemForMember(address) external returns (uint);
    function changeUTILS(address) external;
    function setRewardAddress(address) external;
}