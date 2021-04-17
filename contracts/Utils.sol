// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iVAULT.sol";

contract Utils {

    uint private one = 10**18;
    address public VAULT;

    // struct GlobalDetails {
    //     uint totalStaked;
    //     uint totalVolume;
    //     uint totalFees;
    //     uint unstakeTx;
    //     uint stakeTx;
    //     uint swapTx;
    // }

    // struct PoolDataStruct {
    //     address tokenAddress;
    //     address poolAddress;
    //     uint genesis;
    //     uint baseAmt;
    //     uint tokenAmt;
    //     uint baseAmtStaked;
    //     uint tokenAmtStaked;
    //     uint fees;
    //     uint volume;
    //     uint txCount;
    //     uint poolUnits;
    // }

    constructor () {}
        // Can set vault
    function init(address _vault) public {
        if(VAULT == address(0)){
            require(_vault != address(0));
            VAULT = _vault;
        }
    }
    //====================================SYSTEM FUNCTIONS====================================//
    // VADER FeeOnTransfer
    function getFeeOnTransfer(uint totalSupply, uint maxSupply) public pure returns(uint){
        return calcShare(totalSupply, maxSupply, 100); // 0->100BP
    }

    // function getMemberShare(address token, address member) public view returns(uint baseAmt, uint tokenAmt){
    //     address pool = getPool(token);
    //     uint units = iERC20(pool).balanceOf(member);
    //     return getPoolShare(token, units);
    // }

    // function getPoolShare(address token, uint units) public view returns(uint baseAmt, uint tokenAmt){
    //     address payable pool = getPool(token);
    //     baseAmt = calcShare(units, iERC20(pool).totalSupply(), iVAULT(pool).baseAmt());
    //     tokenAmt = calcShare(units, iERC20(pool).totalSupply(), iVAULT(pool).tokenAmt());
    //     return (baseAmt, tokenAmt);
    // }

    // function getShareOfBaseAmount(address token, address member) public view returns(uint baseAmt){
    //     address payable pool = getPool(token);
    //     uint units = iERC20(pool).balanceOf(member);
    //     return calcShare(units, iERC20(pool).totalSupply(), iVAULT(pool).baseAmt());
    // }
    // function getShareOfTokenAmount(address token, address member) public view returns(uint baseAmt){
    //     address payable pool = getPool(token);
    //     uint units = iERC20(pool).balanceOf(member);
    //     return calcShare(units, iERC20(pool).totalSupply(), iVAULT(pool).tokenAmt());
    // }

    // function getPoolShareAssym(address token, uint units, bool toBase) public view returns(uint baseAmt, uint tokenAmt, uint outputAmt){
    //     address payable pool = getPool(token);
    //     if(toBase){
    //         baseAmt = calcAsymmetricShare(units, iERC20(pool).totalSupply(), iVAULT(pool).baseAmt());
    //         tokenAmt = 0;
    //         outputAmt = baseAmt;
    //     } else {
    //         baseAmt = 0;
    //         tokenAmt = calcAsymmetricShare(units, iERC20(pool).totalSupply(), iVAULT(pool).tokenAmt());
    //         outputAmt = tokenAmt;
    //     }
    //     return (baseAmt, tokenAmt, outputAmt);
    // }

//     function getPoolAge(address token) public view returns (uint daysSinceGenesis){
//         address payable pool = getPool(token);
//         uint genesis = iVAULT(pool).genesis();
//         if(now < genesis + 86400)){
//             return 1;
//         } else {
//             return (now - genesis)) / 86400);
//         }
//     }

//     function getPoolROI(address token) public view returns (uint roi){
//         address payable pool = getPool(token);
//         uint _baseStart = iVAULT(pool).baseAmtStaked() * 2);
//         uint _baseEnd = iVAULT(pool).baseAmt() * 2);
//         uint _ROIS = (_baseEnd * 10000)) / _baseStart);
//         uint _tokenStart = iVAULT(pool).tokenAmtStaked() * 2);
//         uint _tokenEnd = iVAULT(pool).tokenAmt() * 2);
//         uint _ROIA = (_tokenEnd * 10000)) / _tokenStart);
//         return (_ROIS + _ROIA) / 2);
//    }

//    function getPoolAPY(address token) public view returns (uint apy){
//         uint avgROI = getPoolROI(token);
//         uint poolAge = getPoolAge(token);
//         return (avgROI * 365)) / poolAge);
//    }

//     function isMember(address token, address member) public view returns(bool){
//         address payable pool = getPool(token);
//         if (iERC20(pool).balanceOf(member) > 0){
//             return true;
//         } else {
//             return false;
//         }
//     }

    //====================================PRICING====================================//

    function calcValueInBase(address token, uint amount) public view returns (uint){
       (uint _baseAmt, uint _tokenAmt) = iVAULT(VAULT).getPoolAmounts(token);
       return (amount * _baseAmt) / _tokenAmt;
    }

    function calcValueInToken(address token, uint amount) public view returns (uint){
        (uint _baseAmt, uint _tokenAmt) = iVAULT(VAULT).getPoolAmounts(token);
        return (amount * _tokenAmt) / _baseAmt;
    }

//     function calcTokenPPinBase(address token, uint amount) public view returns (uint _output){
//         address payable pool = getPool(token);
//         return  calcTokenPPinBaseWithPool(pool, amount);
//    }

//     function calcBasePPinToken(address token, uint amount) public view returns (uint _output){
//         address payable pool = getPool(token);
//         return  calcValueInBaseWithPool(pool, amount);
//     }

//     function calcTokenPPinBaseWithPool(address payable pool, uint amount) public view returns (uint _output){
//         uint _baseAmt = iVAULT(pool).baseAmt();
//         uint _tokenAmt = iVAULT(pool).tokenAmt();
//         return  calcSwapOutput(amount, _tokenAmt, _baseAmt);
//    }

//     function calcBasePPinTokenWithPool(address payable pool, uint amount) public view returns (uint _output){
//         uint _baseAmt = iVAULT(pool).baseAmt();
//         uint _tokenAmt = iVAULT(pool).tokenAmt();
//         return  calcSwapOutput(amount, _baseAmt, _tokenAmt);
//     }

    //====================================CORE-MATH====================================//

    function calcPart(uint bp, uint total) public pure returns (uint){
        // 10,000 basis points = 100.00%
        require((bp <= 10000) && (bp >= 0), "Must be correct BP");
        return calcShare(bp, 10000, total);
    }

    function calcShare(uint part, uint total, uint amount) public pure returns (uint share){
        // share = amount * part/total
        if(total > 0){
            share = (amount * part) / total;
        }
        return share;
    }

    function calcSwapOutput(uint x, uint X, uint Y) public pure returns (uint){
        // y = (x * X * Y )/(x + X)^2
        uint numerator = (x * X * Y);
        uint denominator = (x + X) * (x + X);
        return (numerator / denominator);
    }

    function calcSwapFee(uint x, uint X, uint Y) public pure returns (uint){
        // fee = (x * x * Y) / (x + X)^2
        uint numerator = (x * x * Y);
        uint denominator = (x + X) * (x + X);
        return (numerator / denominator);
    }
    function calcSwapSlip(uint x, uint X) public pure returns (uint){
        // slip = (x) / (x + X)
        return (x*10000) / (x + X);
    }

    function calcLiquidityUnits(uint b, uint B, uint t, uint T, uint P) public view returns (uint){
        if(P == 0){
            return b;
        } else {
            // units = ((P (t B + T b))/(2 T B)) * slipAdjustment
            // P * (part1 + part2) / (part3) * slipAdjustment
            uint slipAdjustment = getSlipAdustment(b, B, t, T);
            uint part1 = (t * B);
            uint part2 = (T * b);
            uint part3 = (T * B) * 2;
            return (P * part1 + part2) * slipAdjustment / part3 / one;  // Divide by 10**18
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

    function calcAsymmetricShare(uint u, uint U, uint A) public pure returns (uint){
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
    function calcCoverage(uint _B0, uint _T0, uint _B1, uint _T1) public pure returns(uint coverage){
        if(_B1 > 0 && _T1 > 0){
            uint _depositValue = _B0 + (_T0 * _B1) / _T1; // B0+(T0*B1/T1)
            uint _redemptionValue = _B1 + (_T1 * _B1) / _T1; // B1+(T1*B1/T1)
            if(_redemptionValue <= _depositValue){
                coverage = (_depositValue - _redemptionValue);
            }
        }
        return coverage;
    }

}
