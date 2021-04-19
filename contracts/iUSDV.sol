// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iUSDV {
    function ROUTER() external view returns (address);
    function totalWeight() external view returns(uint);
    function totalRewards() external view returns(uint);
    function isMature() external view returns (bool);
    function setParams(uint newEra, uint newDepositTime, uint newDelay, uint newGrantTime) external;
    function grant(address recipient, uint amount) external;
    function convert(uint amount) external returns(uint convertAmount);
    function convertForMember(address member, uint amount) external returns(uint convertAmount);
    function redeem(uint amount) external returns(uint redeemAmount);
    function redeemForMember(address member, uint amount) external returns(uint redeemAmount);
    function deposit(address token, uint amount) external;
    function depositForMember(address token, address member, uint amount) external;
    function harvest(address token) external returns(uint reward);
    function calcCurrentReward(address token, address member) external view returns(uint reward);
    function calcReward(address member) external view returns(uint);
    function withdraw(address token, uint basisPoints) external returns(uint redeemedAmount);
    function reserveUSDV() external view returns(uint);
    function getTokenDeposits(address token) external view returns(uint);
    function getMemberReward(address token, address member) external view returns(uint);
    function getMemberWeight(address member) external view returns(uint);
    function getMemberDeposit(address token, address member) external view returns(uint);
    function getMemberLastTime(address token, address member) external view returns(uint);
}