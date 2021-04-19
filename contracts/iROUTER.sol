// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface iROUTER {
    function setParams(uint newFactor, uint newTime, uint newLimit) external;
    function addLiquidity(address base, uint inputBase, address token, uint inputToken) external returns(uint);
    function removeLiquidity(address base, address token, uint basisPoints) external returns (uint amountBase, uint amountToken);
    function swap(uint inputAmount, address inputToken, address outputToken) external returns (uint outputAmount);
    function swapWithLimit(uint inputAmount, address inputToken, address outputToken, uint slipLimit) external returns (uint outputAmount);
    function swapWithSynths(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth) external returns (uint outputAmount);
    function swapWithSynthsWithLimit(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth, uint slipLimit) external returns (uint outputAmount);
    function getRewardShare(address token) external view returns (uint rewardShare);
    function getReducedShare(uint amount) external view returns(uint);
    function pullIncentives(uint shareVADER, uint shareUSDV) external;
    function getILProtection(address member, address base, address token, uint basisPoints) external view returns(uint protection);
    function getProtection(address member, address token, uint basisPoints, uint coverage) external view returns(uint protection);
    function getCoverage(address member, address token) external view returns (uint);
    function curatePool(address token) external;
    function listAnchor(address token) external;
    function replacePool(address oldToken, address newToken) external;
    function updateAnchorPrice(address token) external;
    function getAnchorPrice() external view returns (uint anchorPrice);
    function getVADERAmount(uint USDVAmount) external view returns (uint vaderAmount);
    function getUSDVAmount(uint vaderAmount) external view returns (uint USDVAmount);
    function reserveVADER() external view returns(uint);
    function reserveUSDV() external view returns(uint);
    function isCurated(address token) external view returns(bool curated);
}