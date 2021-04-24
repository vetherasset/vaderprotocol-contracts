// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iVADER {
    function UTILS() external view returns (address);

    function DAO() external view returns (address);

    function emitting() external view returns (bool);

    function minting() external view returns (bool);

    function secondsPerEra() external view returns (uint256);

    function flipEmissions() external;

    function flipMinting() external;

    function setParams(uint256 newEra, uint256 newCurve) external;

    function setRewardAddress(address newAddress) external;

    function changeUTILS(address newUTILS) external;

    function changeDAO(address newDAO) external;

    function purgeDAO() external;

    function upgrade(uint256 amount) external;

    function redeem() external returns (uint256);

    function redeemToMember(address member) external returns (uint256);
}
