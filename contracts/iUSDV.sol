// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iUSDV {
    function isMature() external view returns (bool);
    function ROUTER() external view returns (address);
    function convert(uint) external returns(uint);
    function convertForMember(address, uint) external returns(uint);
    function redeem(uint) external returns(uint);
    function redeemForMember(address, uint) external returns(uint);
    function totalWeight() external view returns(uint);
    function totalRewards() external view returns(uint);
    function getTokenDeposits(address) external view returns(uint);
    function getMemberReward(address, address) external view returns(uint);
    function getMemberWeight(address) external view returns(uint);
    function getMemberDeposit(address, address) external view returns(uint);
    function getMemberLastTime(address, address) external view returns(uint);
    function grant(address, uint) external;
}