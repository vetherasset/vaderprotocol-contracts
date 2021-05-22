// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iVAULT {
    function totalWeight() external view returns (uint256);

    function setParams(uint256 newDepositTime) external;

    function deposit(address asset, uint256 amount) external;

    function depositForMember(
        address asset,
        address member,
        uint256 amount
    ) external;

    function harvest(address asset) external returns (uint256 reward);

    function calcRewardForAsset(address asset) external view returns(uint256 reward);

    function withdraw(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount);

    function withdrawToVader(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount);

    function calcDepositValueForMember(address asset, address member) external view returns (uint256 value);

    function getMemberDeposit(address member, address asset) external view returns (uint256);

    function getMemberLastTime(address member, address asset) external view returns (uint256);

    function getMemberWeight(address member) external view returns (uint256);

    function getAssetDeposit(address asset) external view returns (uint256);
}
