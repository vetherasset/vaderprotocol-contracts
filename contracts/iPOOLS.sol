// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

interface iPOOLS{
    function pooledVADER() external view returns(uint);
    function pooledUSDV() external view returns(uint);
    function addLiquidity(address, address, address) external returns(uint);
    function removeLiquidity(address, address, uint) external returns (uint, uint);
    function sync(address, address) external;
    function swap(address, address, address, bool) external returns (uint);
    function mintSynth(address, address, address) external returns (uint);
    function burnSynth(address, address, address) external returns (uint);
    function getSynth(address) external returns (address);
    function isSynth(address) external returns (bool);
    function isMember(address) external view returns(bool);
    function isAsset(address) external view returns(bool);
    function isAnchor(address) external view returns(bool);
    function getPoolAmounts(address) external view returns(uint, uint);
    function getBaseAmount(address) external view returns(uint);
    function getTokenAmount(address) external view returns(uint);
    function getUnits(address) external view returns(uint);
    function getMemberUnits(address, address) external view returns(uint);
}