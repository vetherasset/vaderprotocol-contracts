// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iVADER {

    function GovernorAlpha() external view returns (address);

    function Admin() external view returns (address);

    function UTILS() external view returns (address);

    function emitting() external view returns (bool);

    function minting() external view returns (bool);

    function secondsPerEra() external view returns (uint256);

    function era() external view returns(uint256);

    function flipEmissions() external;

    function flipMinting() external;

    function setParams(uint256 newSeconds, uint256 newCurve, uint256 newTailEmissionEra) external;

    function setReserve(address newReserve) external;

    function changeUTILS(address newUTILS) external;

    function changeGovernorAlpha(address newGovernorAlpha) external;

    function purgeGovernorAlpha() external;

    function upgrade(uint256 amount) external;

    function convertToUSDV(uint256 amount) external returns (uint256);

    function convertToUSDVForMember(address member, uint256 amount) external returns (uint256 convertAmount);

    function redeemToVADER(uint256 amount) external returns (uint256);

    function redeemToVADERForMember(address member, uint256 amount) external returns (uint256);
}
