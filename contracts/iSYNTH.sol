// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iSYNTH {
    function mint(address, uint) external;
    function TOKEN() external returns(address);
}