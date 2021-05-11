// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iVAULT {
    function setParams(
        uint256 newEra,
        uint256 newDepositTime,
        uint256 newGrantTime
    ) external;

    function deposit(address synth, uint256 amount) external;

    function depositForMember(
        address synth,
        address member,
        uint256 amount
    ) external;

    function harvest(address synth) external returns (uint256 reward);

    function calcCurrentReward(address synth, address member) external view returns (uint256 reward);

    function calcReward(address synth, address member) external view returns (uint256);

    function withdraw(address synth, uint256 basisPoints) external returns (uint256 redeemedAmount);

    function totalWeight() external view returns (uint256);

    function reserveUSDV() external view returns (uint256);

    function reserveVADER() external view returns (uint256);

    function getMemberDeposit(address member, address synth) external view returns (uint256);

    function getMemberWeight(address member) external view returns (uint256);

    function getMemberLastTime(address member, address synth) external view returns (uint256);
}
