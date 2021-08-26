// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iGovernorAlpha {
    function updateVADER(address newAddress) external;
    function VETHER() external view returns(address);
    function VADER() external view returns(address);
    function USDV() external view returns(address);
    function RESERVE() external view returns(address);
    function VAULT() external view returns(address);
    function ROUTER() external view returns(address);
    function LENDER() external view returns(address);
    function POOLS() external view returns(address);
    function FACTORY() external view returns(address);
    function UTILS() external view returns(address);
    function TIMELOCK() external view returns(address);
}
