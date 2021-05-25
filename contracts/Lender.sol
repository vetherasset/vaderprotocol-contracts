// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/SafeERC20.sol";
import "./interfaces/iERC20.sol";
import "./interfaces/iDAO.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iSYNTH.sol";

import "hardhat/console.sol";

contract Lender {

    using SafeERC20 for ExternalERC20;

    address public immutable VADER;

    mapping(address => CollateralDetails) private mapMember_Collateral;
    mapping(address => mapping(address => uint256)) private mapCollateralDebt_Collateral;
    mapping(address => mapping(address => uint256)) private mapCollateralDebt_Debt;
    mapping(address => mapping(address => uint256)) private mapCollateralDebt_interestPaid;
    mapping(address => mapping(address => uint256)) private mapCollateralAsset_NextEra;

    struct CollateralDetails {
        mapping(address => DebtDetails) mapCollateral_Debt;
    }
    struct DebtDetails {
        mapping(address => uint256) debt; //assetC > AssetD > AmountDebt
        mapping(address => uint256) collateral; //assetC > AssetD > AmountCol
        // mapping(address =>uint) assetCollateralDeposit; //assetC > AssetD > AmountCol
        // mapping(address =>uint) timeBorrowed; // assetC > AssetD > time
        // mapping(address =>uint) currentDay; // assetC > AssetD > time
    }

    event AddCollateral(
        address indexed member,
        address indexed collateralAsset,
        uint256 collateralLocked,
        address indexed debtAsset,
        uint256 debtIssued
    );
    event RemoveCollateral(
        address indexed member,
        address indexed collateralAsset,
        uint256 collateralUnlocked,
        address indexed debtAsset,
        uint256 debtReturned
    );

    constructor(address _vader) {
        VADER = _vader;
    }

    //======================================LENDING=========================================//

    // Draw debt for self
    function borrow(
        uint256 amount,
        address collateralAsset,
        address debtAsset
    ) external returns (uint256) {
        return borrowForMember(msg.sender, amount, collateralAsset, debtAsset);
    }

    function borrowForMember(
        address member,
        uint256 amount,
        address collateralAsset,
        address debtAsset
    ) public returns (uint256) {
        iUTILS(UTILS()).assetChecks(collateralAsset, debtAsset);
        uint256 _collateral = _handleTransferIn(member, collateralAsset, amount); // get collateral
        (uint256 _debtIssued, uint256 _baseBorrowed) =
            iUTILS(UTILS()).getCollateralValueInBase(member, _collateral, collateralAsset, debtAsset);
        mapCollateralDebt_Collateral[collateralAsset][debtAsset] += _collateral; // Record collateral
        mapCollateralDebt_Debt[collateralAsset][debtAsset] += _debtIssued; // Record debt
        _addDebtToMember(member, _collateral, collateralAsset, _debtIssued, debtAsset); // Update member details
        if (collateralAsset == VADER || iPOOLS(POOLS()).isAnchor(debtAsset)) {
            iRESERVE(RESERVE()).requestFundsStrict(VADER, POOLS(), _baseBorrowed);
            iPOOLS(POOLS()).swap(VADER, debtAsset, member, false); // Execute swap to member
        } else if (collateralAsset == USDV() || iPOOLS(POOLS()).isAsset(debtAsset)) {
            iRESERVE(RESERVE()).requestFundsStrict(USDV(), POOLS(), _baseBorrowed); // Send to pools
            iPOOLS(POOLS()).swap(USDV(), debtAsset, member, false); // Execute swap to member
        }
        emit AddCollateral(member, collateralAsset, amount, debtAsset, _debtIssued); // Event
        payInterest(collateralAsset, debtAsset);
        return _debtIssued;
    }

    // Repay for self
    function repay(
        uint256 amount,
        address collateralAsset,
        address debtAsset
    ) external returns (uint256) {
        return repayForMember(msg.sender, amount, collateralAsset, debtAsset);
    }

    // Repay for member
    function repayForMember(
        address member,
        uint256 basisPoints,
        address collateralAsset,
        address debtAsset
    ) public returns (uint256) {
        uint256 _amount = iUTILS(UTILS()).calcPart(basisPoints, getMemberDebt(member, collateralAsset, debtAsset));
        uint256 _debt = moveTokenToPools(debtAsset, _amount); // Get Debt
        if (collateralAsset == VADER || iPOOLS(POOLS()).isAnchor(debtAsset)) {
            iPOOLS(POOLS()).swap(VADER, debtAsset, RESERVE(), true); // Swap Debt to Base back here
        } else if (collateralAsset == USDV() || iPOOLS(POOLS()).isAsset(debtAsset)) {
            iPOOLS(POOLS()).swap(USDV(), debtAsset, RESERVE(), true); // Swap Debt to Base back here
        }
        (uint256 _collateralUnlocked, uint256 _memberInterestShare) =
            iUTILS(UTILS()).getDebtValueInCollateral(member, _debt, collateralAsset, debtAsset); // Unlock collateral that is pro-rata to re-paid debt ($50/$100 = 50%)
        mapCollateralDebt_Collateral[collateralAsset][debtAsset] -= _collateralUnlocked; // Update collateral
        mapCollateralDebt_Debt[collateralAsset][debtAsset] -= _debt; // Update debt
        mapCollateralDebt_interestPaid[collateralAsset][debtAsset] -= _memberInterestShare;
        _removeDebtFromMember(member, _collateralUnlocked, collateralAsset, _debt, debtAsset); // Remove
        emit RemoveCollateral(member, collateralAsset, _collateralUnlocked, debtAsset, _debt);
        _handleTransferOut(member, collateralAsset, _collateralUnlocked);
        payInterest(collateralAsset, debtAsset);
        return _collateralUnlocked;
    }

    // Called once a day to pay interest
    function payInterest(address collateralAsset, address debtAsset) internal {
        if (block.timestamp >= getNextEraTime(collateralAsset, debtAsset) && emitting()) {
            // If new Era
            uint256 _timeElapsed = block.timestamp - mapCollateralAsset_NextEra[collateralAsset][debtAsset];
            mapCollateralAsset_NextEra[collateralAsset][debtAsset] = block.timestamp + iVADER(VADER).secondsPerEra();
            uint256 _interestOwed = iUTILS(UTILS()).getInterestOwed(collateralAsset, debtAsset, _timeElapsed);
            mapCollateralDebt_interestPaid[collateralAsset][debtAsset] += _interestOwed;
            _removeCollateral(_interestOwed, collateralAsset, debtAsset);
            if (isBase(collateralAsset)) {
                iERC20(collateralAsset).transfer(POOLS(), _interestOwed); // safeErc20 not needed; bases trusted
                iPOOLS(POOLS()).sync(collateralAsset, debtAsset);
            } else if (iPOOLS(POOLS()).isSynth(collateralAsset)) {
                iERC20(collateralAsset).transfer(POOLS(), _interestOwed); // safeErc20 not needed; synths trusted
                iPOOLS(POOLS()).syncSynth(iSYNTH(collateralAsset).TOKEN());
            }
        }
    }

    function checkLiquidate() external {
        // get member remaining Collateral: originalDeposit - shareOfInterestPayments
        // if remainingCollateral <= 101% * debtValueInCollateral
        // purge, send remaining collateral to liquidator
    }

    // function purgeMember() public {

    // }

    function _addDebtToMember(
        address _member,
        uint256 _collateral,
        address _collateralAsset,
        uint256 _debt,
        address _debtAsset
    ) internal {
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] += _debt;
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] += _collateral;
    }

    function _removeDebtFromMember(
        address _member,
        uint256 _collateral,
        address _collateralAsset,
        uint256 _debt,
        address _debtAsset
    ) internal {
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] -= _debt;
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] -= _collateral;
    }

    function _removeCollateral(
        uint256 _collateral,
        address _collateralAsset,
        address _debtAsset
    ) internal {
        mapCollateralDebt_Collateral[_collateralAsset][_debtAsset] -= _collateral; // Record collateral
    }

     //======================================ASSETS=========================================//   

    // Move funds in
    function moveTokenToPools(address _token, uint256 _amount) internal returns (uint256 safeAmount) {
        if (_token == VADER || _token == USDV() || iPOOLS(POOLS()).isSynth(_token)) {
            safeAmount = _amount;
            iERC20(_token).transferFrom(msg.sender, POOLS(), _amount); // safeErc20 not needed; bases and synths trusted
        } else {
            uint256 _startBal = ExternalERC20(_token).balanceOf(POOLS());
            ExternalERC20(_token).safeTransferFrom(msg.sender, POOLS(), _amount);
            safeAmount = ExternalERC20(_token).balanceOf(POOLS()) - _startBal;
        }
    }

    // Get Collateral
    function _handleTransferIn(
        address _member,
        address _collateralAsset,
        uint256 _amount
    ) internal returns (uint256 _inputAmount) {
        if (isBase(_collateralAsset) || iPOOLS(POOLS()).isSynth(_collateralAsset)) {
            _inputAmount = _getFunds(_collateralAsset, _amount); // Get funds
        } else if (isPool(_collateralAsset)) {
            iPOOLS(POOLS()).lockUnits(_amount, _collateralAsset, _member); // Lock units to protocol
            _inputAmount = _amount;
        }
    }

    // Send Collateral
    function _handleTransferOut(
        address _member,
        address _collateralAsset,
        uint256 _amount
    ) internal {
        if (isBase(_collateralAsset) || iPOOLS(POOLS()).isSynth(_collateralAsset)) {
            require(iERC20(_collateralAsset).transfer(_member, _amount)); // Send Base
        } else if (isPool(_collateralAsset)) {
            iPOOLS(POOLS()).unlockUnits(_amount, _collateralAsset, _member); // Unlock units to member
        }
    }

    // @dev Assumes `_token` is trusted (is a base asset or synth) and supports
    function _getFunds(address _token, uint256 _amount) internal returns (uint256) {
        uint256 _balance = iERC20(_token).balanceOf(address(this));
        require(iERC20(_token).transferFrom(msg.sender, address(this), _amount)); // safeErc20 not needed; _token trusted
        return iERC20(_token).balanceOf(address(this)) - _balance;
    }


    //======================================HELPERS=========================================//

    function isBase(address token) public view returns (bool base) {
        return token == VADER || token == USDV();
    }

    function isPool(address token) public view returns (bool) {
        return iPOOLS(POOLS()).isAnchor(token) || iPOOLS(POOLS()).isAsset(token);
    }

    function emitting() public view returns (bool) {
        return iVADER(VADER).emitting();
    }

    function getMemberCollateral(
        address member,
        address collateralAsset,
        address debtAsset
    ) external view returns (uint256) {
        return mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].collateral[debtAsset];
    }

    function getMemberDebt(
        address member,
        address collateralAsset,
        address debtAsset
    ) public view returns (uint256) {
        return mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].debt[debtAsset];
    }

    function getSystemCollateral(address collateralAsset, address debtAsset) external view returns (uint256) {
        return mapCollateralDebt_Collateral[collateralAsset][debtAsset];
    }

    function getSystemDebt(address collateralAsset, address debtAsset) external view returns (uint256) {
        return mapCollateralDebt_Debt[collateralAsset][debtAsset];
    }

    function getSystemInterestPaid(address collateralAsset, address debtAsset) external view returns (uint256) {
        return mapCollateralDebt_interestPaid[collateralAsset][debtAsset];
    }

    function getNextEraTime(address collateralAsset, address debtAsset) public view returns (uint256) {
        return mapCollateralAsset_NextEra[collateralAsset][debtAsset];
    }

    function USDV() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).USDV();
    }
    function RESERVE() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).RESERVE();
    }
    function POOLS() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).POOLS();
    }
    function UTILS() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).UTILS();
    }

}
    