// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iPOOLS {
    function pooledVADER() external view returns (uint256);

    function pooledUSDV() external view returns (uint256);

    function addLiquidity(
        address base,
        address token,
        address member
    ) external returns (uint256 liquidityUnits);

    function removeLiquidity(
        address base,
        address token,
        uint256 basisPoints,
        address member
    ) external returns (uint256 units, uint256 outputBase, uint256 outputToken);

    function sync(address token, address pool) external;

    function swap(
        address base,
        address token,
        address member,
        bool toBase
    ) external returns (uint256 outputAmount);

    function deploySynth(address token) external;

    function mintSynth(
        address token,
        address member
    ) external returns (uint256 outputAmount);

    function burnSynth(
        address token,
        address member
    ) external returns (uint256 outputBase);

    function syncSynth(address token) external;

    function lockUnits(
        uint256 units,
        address token,
        address member
    ) external;

    function unlockUnits(
        uint256 units,
        address token,
        address member
    ) external;

    function isAsset(address token) external view returns (bool);

    function isAnchor(address token) external view returns (bool);

    function getPoolAmounts(address token) external view returns (uint256, uint256);

    function getBaseAmount(address token) external view returns (uint256);

    function getTokenAmount(address token) external view returns (uint256);

    function getUnits(address token) external view returns (uint256);

    function getMemberUnits(address token, address member) external view returns (uint256);

    function getSynth(address token) external returns (address);

    function isSynth(address token) external returns (bool);
}
