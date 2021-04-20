// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iPOOLS.sol";

contract Utils {

    uint private one = 10**18;
    address public POOLS;

    constructor () {}

    function init(address _pool) public {
        if(POOLS == address(0)){
            POOLS = _pool;
        }
    }
    //====================================SYSTEM FUNCTIONS====================================//
    // VADER FeeOnTransfer
    function getFeeOnTransfer(uint totalSupply, uint maxSupply) external pure returns(uint){
        return calcShare(totalSupply, maxSupply, 100); // 0->100BP
    }

    //====================================PRICING====================================//

    function calcValueInBase(address token, uint amount) external view returns (uint){
       (uint _baseAmt, uint _tokenAmt) = iPOOLS(POOLS).getPoolAmounts(token);
       return (amount * _baseAmt) / _tokenAmt;
    }

    function calcValueInToken(address token, uint amount) external view returns (uint){
        (uint _baseAmt, uint _tokenAmt) = iPOOLS(POOLS).getPoolAmounts(token);
        return (amount * _tokenAmt) / _baseAmt;
    }
    function calcValueOfTokenInToken(address token1, uint amount, address token2) external view returns (uint){
        (uint _baseAmt1, uint _tokenAmt1) = iPOOLS(POOLS).getPoolAmounts(token1);
        uint _amount2 = (amount * _baseAmt1) / _tokenAmt1;
        (uint _baseAmt2, uint _tokenAmt2) = iPOOLS(POOLS).getPoolAmounts(token2);
        return (_amount2 * _tokenAmt2) / _baseAmt2;
    }

    function calcSwapValueInBase(address token, uint amount) external view returns (uint){
        (uint _baseAmt, uint _tokenAmt) = iPOOLS(POOLS).getPoolAmounts(token);
        return calcSwapOutput(amount, _tokenAmt, _baseAmt);
    }
    function calcSwapValueInToken(address token, uint amount) external view returns (uint){
        (uint _baseAmt, uint _tokenAmt) = iPOOLS(POOLS).getPoolAmounts(token);
        return calcSwapOutput(amount, _baseAmt, _tokenAmt);
    }

    //====================================CORE-MATH====================================//

    function calcPart(uint bp, uint total) external pure returns (uint){
        // 10,000 basis points = 100.00%
        require((bp <= 10000) && (bp >= 0), "Must be correct BP");
        return calcShare(bp, 10000, total);
    }

    function calcShare(uint part, uint total, uint amount) public pure returns (uint share){
        // share = amount * part/total
        if(total > 0){
            share = (amount * part) / total;
        }
    }

    function calcSwapOutput(uint x, uint X, uint Y) public pure returns (uint){
        // y = (x * X * Y )/(x + X)^2
        uint numerator = (x * X * Y);
        uint denominator = (x + X) * (x + X);
        return (numerator / denominator);
    }

    function calcSwapFee(uint x, uint X, uint Y) external pure returns (uint){
        // fee = (x * x * Y) / (x + X)^2
        uint numerator = (x * x * Y);
        uint denominator = (x + X) * (x + X);
        return (numerator / denominator);
    }
    function calcSwapSlip(uint x, uint X) external pure returns (uint){
        // slip = (x) / (x + X)
        return (x*10000) / (x + X);
    }

    function calcLiquidityUnits(uint b, uint B, uint t, uint T, uint P) external view returns (uint){
        if(P == 0){
            return b;
        } else {
            // units = ((P (t B + T b))/(2 T B)) * slipAdjustment
            // P * (part1 + part2) / (part3) * slipAdjustment
            uint slipAdjustment = getSlipAdustment(b, B, t, T);
            uint part1 = (t * B);
            uint part2 = (T * b);
            uint part3 = (T * B) * 2;
            uint _units = (((P * part1) + part2) / part3);
            return (_units * slipAdjustment) / one;  // Divide by 10**18
        }
    }

    function getSlipAdustment(uint b, uint B, uint t, uint T) public view returns (uint){
        // slipAdjustment = (1 - ABS((B t - b T)/((2 b + B) (t + T))))
        // 1 - ABS(part1 - part2)/(part3 * part4))
        uint part1 = B * t;
        uint part2 = b * T;
        uint part3 = (b * 2) + B;
        uint part4 = t + T;
        uint numerator;
        if(part1 > part2){
            numerator = (part1 - part2);
        } else {
            numerator = (part2 - part1);
        }
        uint denominator = (part3 * part4);
        return one - (numerator * one) / denominator; // Multiply by 10**18
    }

    function calcSynthUnits(uint b, uint B, uint P) external pure returns(uint){
        // (P * b)/(2*(b + B))
        return (P * b) / (2 * (b + B));
    }

    function calcAsymmetricShare(uint u, uint U, uint A) external pure returns (uint){
        // share = (u * U * (2 * A^2 - 2 * U * u + U^2))/U^3
        // (part1 * (part2 - part3 + part4)) / part5
        uint part1 = (u * A);
        uint part2 = ((U * U) * 2);
        uint part3 = ((U * u) * 2);
        uint part4 = (u * u);
        uint numerator = ((part1 * part2) - part3) + part4;
        uint part5 = ((U * U) * U);
        return (numerator / part5);
    }
    function calcCoverage(uint B0, uint T0, uint B1, uint T1) external pure returns(uint coverage){
        if(B0 > 0 && T1 > 0){
            uint _depositValue = B0 + (T0 * B1) / T1; // B0+(T0*B1/T1)
            uint _redemptionValue = B1 + (T1 * B1) / T1; // B1+(T1*B1/T1)
            if(_redemptionValue <= _depositValue){
                coverage = (_depositValue - _redemptionValue);
            }
        }
    }

}