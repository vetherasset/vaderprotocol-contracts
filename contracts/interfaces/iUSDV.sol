// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iUSDV {
    function ROUTER() external view returns (address);

    function isMature() external view returns (bool);

    function setParams(uint256 newDelay) external;

    function convert(uint256 amount) external returns (uint256 convertAmount);

    function convertForMember(address member, uint256 amount) external returns (uint256 convertAmount);

    function redeem(uint256 amount) external returns (uint256 redeemAmount);

    function redeemForMember(address member, uint256 amount) external returns (uint256 redeemAmount);
}
