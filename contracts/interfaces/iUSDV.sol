// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iUSDV {
    function isMature() external view returns (bool);

    function setParams(uint256 newDelay) external;

    function updateVADER(address newAddress) external;

    function convertToUSDV(uint256 amount) external returns (uint256);

    function convertToUSDVForMember(address member, uint256 amount) external returns (uint256);

    function convertToUSDVDirectly() external returns (uint256 convertAmount);

    function convertToUSDVForMemberDirectly(address member) external returns (uint256 convertAmount);
}
