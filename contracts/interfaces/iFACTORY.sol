// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iFACTORY{
    function deploySynth(address) external returns(address);
    function mintSynth(address, address, uint) external returns(bool);
    function getSynth(address) external returns (address);
    function isSynth(address) external returns (bool);
}