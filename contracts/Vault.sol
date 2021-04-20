// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.3;


// contract Vault {

//     constructor(){}

//     function init(address _pool) public {
//         require(inited == false);
//         inited = true;
//         POOLS = _pool;
//     }

//     // Draw debt for self
//     function drawDebt(uint amount, address collateralAsset, address debtAsset) public payable returns (uint) {
//         return drawDebtForMember(amount, collateralAsset, debtAsset, msg.sender);
//     }
//     // Draw debt for member
//     // transferInCollateral
//     // get collateral value, subtract from reserve
//     // get swapValue as debt
//     // record member's debtAmount
//     // add to CDP
//     // send debtAsset to member

//     function drawDebtForMember(uint amount, address collateralAsset, address debtAsset, address member) public payable returns (uint256 debtAssetIssued) {
//         (uint _actualInputCollateral, uint _baseBorrow) = _handleTransferInCol(amount, collateralAsset);
//         require(_baseBorrow <= reserve, '!Reserve');
//         reserve -= _baseBorrow;
//         debtAssetIssued = iPOOLS(POOLS).swap();
//         _incrCDP(_actualInputCollateral, collateralAsset, debtAssetIssued, debtAsset);
//         _incrMemberDetails(member, _actualInputCollateral, collateralAsset, debtAssetIssued, debtAsset); //update member details
//         iBEP20(assetD).transfer(member, _assetDebtIssued);
//         emit AddCollateral(amount, debtAsset, _assetDebtIssued);
//         return debtAssetIssued;
//     }


//     function _handleTransferInCol( uint256 _amount, address _collateralAsset) internal returns(uint256 _actual, uint _borrowedBase){
//         if(_amount > 0) {
//                 uint _collateralAdjusted = _amount.mul(6666).div(10000); // 150% collateral Ratio
//             if(_collateralAsset == BASE){
//                 _borrowedBase = _collateralAdjusted;
//                 getFunds(_collateralAsset, _amount);
//             // }else if(isUnits()){
//             //      _borrowedBase = iUTILS(UTILS()).calcAsymmetricValueBase(_collateralAsset, _collateralAdjusted);// calc units to BASE
//             //     getFunds(_collateralAsset, _amount);
//             // }else if(isSynth()){
//             //     _borrowedBase = iUTILS(UTILS()).calcSwapValueInBaseWithSYNTH(_collateralAsset, _collateralAdjusted);
//             //     getFunds(_collateralAsset, _amount);
//             // }else{
//             //      return (0,0);
//             }
//         }
//         return (_amount, _borrowedBase);
//     }

// }