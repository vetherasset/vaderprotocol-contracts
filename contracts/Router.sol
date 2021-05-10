// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iDAO.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iSYNTH.sol";

import "hardhat/console.sol";

contract Router {
    // Parameters

    uint256 private constant one = 10**18;
    uint256 public rewardReductionFactor;
    uint256 public timeForFullProtection;

    uint256 public curatedPoolLimit;
    uint256 public curatedPoolCount;
    mapping(address => bool) private _isCurated;

    address public VADER;

    uint256 public anchorLimit;
    uint256 public insidePriceLimit;
    uint256 public outsidePriceLimit;
    address[] public arrayAnchors;
    uint256[] public arrayPrices;
    mapping(address => uint) public mapAnchorAddress_arrayAnchorsIndex1; // 1-based indexes

    mapping(address => mapping(address => uint256)) public mapMemberToken_depositBase;
    mapping(address => mapping(address => uint256)) public mapMemberToken_depositToken;
    mapping(address => mapping(address => uint256)) public mapMemberToken_lastDeposited;

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

    event PoolReward(address indexed base, address indexed token, uint256 amount);
    event Protection(address indexed member, uint256 amount);
    event Curated(address indexed curator, address indexed token);

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

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO() || msg.sender == DEPLOYER(), "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
 
    constructor() {}

    // Init
    function init(address _vader) external {
        if(VADER == address(0)){
            VADER = _vader;
            rewardReductionFactor = 1;
            timeForFullProtection = 1; //8640000; //100 days
            curatedPoolLimit = 1;
            anchorLimit = 5;
            insidePriceLimit = 200;
            outsidePriceLimit = 500;
        }
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(
        uint256 newFactor,
        uint256 newTime,
        uint256 newLimit
    ) external onlyDAO {
        rewardReductionFactor = newFactor;
        timeForFullProtection = newTime;
        curatedPoolLimit = newLimit;
    }

    function setAnchorParams(
        uint256 newLimit,
        uint256 newInside,
        uint256 newOutside
    ) external onlyDAO {
        anchorLimit = newLimit;
        insidePriceLimit = newInside;
        outsidePriceLimit = newOutside;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(
        address base,
        uint256 inputBase,
        address token,
        uint256 inputToken
    ) external returns (uint256) {
        iRESERVE(RESERVE()).checkReserve();
        uint256 _actualInputBase = moveTokenToPools(base, inputBase);
        uint256 _actualInputToken = moveTokenToPools(token, inputToken);
        addDepositData(msg.sender, token, _actualInputBase, _actualInputToken);
        return iPOOLS(POOLS()).addLiquidity(base, token, msg.sender);
    }

    function removeLiquidity(
        address base,
        address token,
        uint256 basisPoints
    ) external returns (uint256 units, uint256 amountBase, uint256 amountToken) {
        uint256 _protection = getILProtection(msg.sender, base, token, basisPoints);
        if(_protection > 0){
            iRESERVE(RESERVE()).requestFunds(base, POOLS(), _protection);
            iPOOLS(POOLS()).addLiquidity(base, token, msg.sender);
            mapMemberToken_depositBase[msg.sender][token] += _protection;
        }
        (units, amountBase, amountToken) = iPOOLS(POOLS()).removeLiquidity(base, token, basisPoints);
        removeDepositData(msg.sender, token, basisPoints, _protection);
        iRESERVE(RESERVE()).checkReserve();
    }

    //=======================================SWAP===========================================//

    function swap(
        uint256 inputAmount,
        address inputToken,
        address outputToken
    ) external returns (uint256 outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, 10000);
    }

    function swapWithLimit(
        uint256 inputAmount,
        address inputToken,
        address outputToken,
        uint256 slipLimit
    ) external returns (uint256 outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, slipLimit);
    }

    function swapWithSynths(
        uint256 inputAmount,
        address inputToken,
        bool inSynth,
        address outputToken,
        bool outSynth
    ) external returns (uint256 outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, inSynth, outputToken, outSynth, 10000);
    }

    function swapWithSynthsWithLimit(
        uint256 inputAmount,
        address inputToken,
        bool inSynth,
        address outputToken,
        bool outSynth,
        uint256 slipLimit
    ) public returns (uint256 outputAmount) {
        address _member = msg.sender;
        if (!inSynth) {
            moveTokenToPools(inputToken, inputAmount);
        } else {
            moveTokenToPools(iPOOLS(POOLS()).getSynth(inputToken), inputAmount);
        }
        address _base;
        if (iPOOLS(POOLS()).isAnchor(inputToken) || iPOOLS(POOLS()).isAnchor(outputToken)) {
            _base = VADER;
        } else {
            _base = USDV();
        }
        if (isBase(outputToken)) {
            // Token||Synth -> BASE
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS()).getTokenAmount(inputToken)) <= slipLimit);
            if (!inSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, inputToken, _member, true);
            } else {
                outputAmount = iPOOLS(POOLS()).burnSynth(_base, inputToken, _member);
            }
        } else if (isBase(inputToken)) {
            // BASE -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS()).getBaseAmount(outputToken)) <= slipLimit);
            if (!outSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS()).mintSynth(_base, outputToken, _member);
            }
        } else { // !isBase(inputToken) && !isBase(outputToken)
            // Token||Synth -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS()).getTokenAmount(inputToken)) <= slipLimit);
            if (!inSynth) {
                iPOOLS(POOLS()).swap(_base, inputToken, POOLS(), true);
            } else {
                iPOOLS(POOLS()).burnSynth(_base, inputToken, POOLS());
            }
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS()).getBaseAmount(outputToken)) <= slipLimit);
            if (!outSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS()).mintSynth(_base, outputToken, _member);
            }
        }
        _handlePoolReward(_base, inputToken);
        _handlePoolReward(_base, outputToken);
        _handleAnchorPriceUpdate(inputToken);
        _handleAnchorPriceUpdate(outputToken);
    }

    //====================================INCENTIVES========================================//

    function _handlePoolReward(address _base, address _token) internal {
        if (!isBase(_token)) {
            // USDV or VADER is never a pool
            uint256 _reward = iUTILS(UTILS()).getRewardShare(_token, rewardReductionFactor);
            iRESERVE(RESERVE()).requestFunds(_base, POOLS(), _reward);
            iPOOLS(POOLS()).sync(_base, _token);
            emit PoolReward(_base, _token, _reward);
        }
    }

    //=================================IMPERMANENT LOSS=====================================//

    function addDepositData(
        address member,
        address token,
        uint256 amountBase,
        uint256 amountToken
    ) internal {
        mapMemberToken_depositBase[member][token] += amountBase;
        mapMemberToken_depositToken[member][token] += amountToken;
        mapMemberToken_lastDeposited[member][token] = block.timestamp;
    }

    function removeDepositData(
        address member,
        address token,
        uint256 basisPoints,
        uint256 protection
    ) internal {
        mapMemberToken_depositBase[member][token] += protection;
        uint256 _baseToRemove = iUTILS(UTILS()).calcPart(basisPoints, mapMemberToken_depositBase[member][token]);
        uint256 _tokenToRemove = iUTILS(UTILS()).calcPart(basisPoints, mapMemberToken_depositToken[member][token]);
        mapMemberToken_depositBase[member][token] -= _baseToRemove;
        mapMemberToken_depositToken[member][token] -= _tokenToRemove;
    }

    function getILProtection(
        address member,
        address base,
        address token,
        uint256 basisPoints
    ) public view returns (uint256 protection) {
        protection = iUTILS(UTILS()).getProtection(member, token, basisPoints, timeForFullProtection);
        if (base == VADER) {
            if (protection >= reserveVADER()) {
                protection = reserveVADER(); // In case reserve is running out
            }
        } else {
            if (protection >= reserveUSDV()) {
                protection = reserveUSDV(); // In case reserve is running out
            }
        }
    }

    //=====================================CURATION==========================================//

    function curatePool(address token) external {
        require(iPOOLS(POOLS()).isAsset(token) || iPOOLS(POOLS()).isAnchor(token));
        if (!isCurated(token)) {
            if (curatedPoolCount < curatedPoolLimit) {
                // Limit
                _isCurated[token] = true;
                curatedPoolCount += 1;
            }
        }
        emit Curated(msg.sender, token);
    }

    function replacePool(address oldToken, address newToken) external {
        require(iPOOLS(POOLS()).isAsset(newToken));
        if (iPOOLS(POOLS()).getBaseAmount(newToken) > iPOOLS(POOLS()).getBaseAmount(oldToken)) {
            // Must be deeper
            _isCurated[oldToken] = false;
            _isCurated[newToken] = true;
            emit Curated(msg.sender, newToken);
        }
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) external {
        require(arrayAnchors.length < anchorLimit); // Limit
        require(iPOOLS(POOLS()).isAnchor(token)); // Must be anchor
        arrayAnchors.push(token); // Add
        mapAnchorAddress_arrayAnchorsIndex1[token] = arrayAnchors.length; // Store 1-based index
        arrayPrices.push(iUTILS(UTILS()).calcValueInBase(token, one));
        _isCurated[token] = true;
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) external {
        require(newToken != oldToken, "New token not new");
        uint idx1 = mapAnchorAddress_arrayAnchorsIndex1[oldToken];
        require(idx1 != 0, "No such old token");
        require(iPOOLS(POOLS()).isAnchor(newToken), "Not anchor");
        require((iPOOLS(POOLS()).getBaseAmount(newToken) > iPOOLS(POOLS()).getBaseAmount(oldToken)), "Not deeper");
        iUTILS(UTILS()).requirePriceBounds(oldToken, outsidePriceLimit, false, getAnchorPrice()); // if price oldToken >5%
        iUTILS(UTILS()).requirePriceBounds(newToken, insidePriceLimit, true, getAnchorPrice()); // if price newToken <2%
        _isCurated[oldToken] = false;
        _isCurated[newToken] = true;
        arrayAnchors[idx1 - 1] = newToken;
        updateAnchorPrice(newToken);
    }

    // Anyone to update prices
    function updateAnchorPrice(address token) public {
        uint idx1 = mapAnchorAddress_arrayAnchorsIndex1[token];
        if (idx1 != 0) {
            arrayPrices[idx1 - 1] = iUTILS(UTILS()).calcValueInBase(token, one);
        }
    }

    function _handleAnchorPriceUpdate(address _token) internal {
        if (iPOOLS(POOLS()).isAnchor(_token)) {
            updateAnchorPrice(_token);
        }
    }

    // Price of 1 VADER in USD
    function getAnchorPrice() public view returns (uint256 anchorPrice) {
        // if array len odd  3/2 = 1; 5/2 = 2
        // if array len even 2/2 = 1; 4/2 = 2
        uint _anchorMiddle = arrayPrices.length/2;
        uint256[] memory _sortedAnchorFeed = iUTILS(UTILS()).sortArray(arrayPrices); // Sort price array, no need to modify storage
        if(arrayPrices.length == 0) {
            anchorPrice = one; // Edge case for first USDV mint
        } else if(arrayPrices.length & 0x1 == 0x1) { // arrayPrices.length is odd
            anchorPrice = _sortedAnchorFeed[_anchorMiddle]; // Return the middle
        } else { // arrayPrices.length is even
            anchorPrice = (_sortedAnchorFeed[_anchorMiddle] / 2) + (_sortedAnchorFeed[_anchorMiddle - 1] / 2); // Return the average of middle pair
        }
    }

    // The correct amount of Vader for an input of USDV
    function getVADERAmount(uint256 USDVAmount) external view returns (uint256 vaderAmount) {
        uint256 _price = getAnchorPrice();
        return (_price * USDVAmount) / one;
    }

    // The correct amount of USDV for an input of VADER
    function getUSDVAmount(uint256 vaderAmount) external view returns (uint256 USDVAmount) {
        uint256 _price = getAnchorPrice();
        return (vaderAmount * one) / _price;
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
                iERC20(collateralAsset).transfer(POOLS(), _interestOwed);
                iPOOLS(POOLS()).sync(collateralAsset, debtAsset);
            } else if (iPOOLS(POOLS()).isSynth(collateralAsset)) {
                iERC20(collateralAsset).transfer(POOLS(), _interestOwed);
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
            _sendFunds(_collateralAsset, _member, _amount); // Send Base
        } else if (isPool(_collateralAsset)) {
            iPOOLS(POOLS()).unlockUnits(_amount, _collateralAsset, _member); // Unlock units to member
        }
    }

    function _getFunds(address _token, uint256 _amount) internal returns (uint256) {
        uint256 _balance = iERC20(_token).balanceOf(address(this));
        if (tx.origin == msg.sender) {
            require(iERC20(_token).transferTo(address(this), _amount));
        } else {
            require(iERC20(_token).transferFrom(msg.sender, address(this), _amount));
        }
        return iERC20(_token).balanceOf(address(this)) - _balance;
    }

    function _sendFunds(
        address _token,
        address _member,
        uint256 _amount
    ) internal {
        require(iERC20(_token).transfer(_member, _amount));
    }

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

    //======================================HELPERS=========================================//

    function isBase(address token) public view returns (bool base) {
        return token == VADER || token == USDV();
    }

    function reserveUSDV() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveUSDV(); // Balance
    }

    function reserveVADER() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveVADER(); // Balance
    }

    // Optionality
    function moveTokenToPools(address _token, uint256 _amount) internal returns (uint256 safeAmount) {
        if (_token == VADER || _token == USDV() || iPOOLS(POOLS()).isSynth(_token)) {
            safeAmount = _amount;
            if (tx.origin == msg.sender) {
                iERC20(_token).transferTo(POOLS(), _amount);
            } else {
                iERC20(_token).transferFrom(msg.sender, POOLS(), _amount);
            }
        } else {
            uint256 _startBal = iERC20(_token).balanceOf(POOLS());
            iERC20(_token).transferFrom(msg.sender, POOLS(), _amount);
            safeAmount = iERC20(_token).balanceOf(POOLS()) - _startBal;
        }
    }


    function emitting() public view returns (bool) {
        return iVADER(VADER).emitting();
    }

    function isCurated(address token) public view returns (bool) {
        return _isCurated[token];
    }

    function isPool(address token) public view returns (bool) {
        return iPOOLS(POOLS()).isAnchor(token) || iPOOLS(POOLS()).isAsset(token);
    }

    function getMemberBaseDeposit(address member, address token) external view returns (uint256) {
        return mapMemberToken_depositBase[member][token];
    }

    function getMemberTokenDeposit(address member, address token) external view returns (uint256) {
        return mapMemberToken_depositToken[member][token];
    }

    function getMemberLastDeposit(address member, address token) external view returns (uint256) {
        return mapMemberToken_lastDeposited[member][token];
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

    function DAO() internal view returns(address){
        return iVADER(VADER).DAO();
    }
    function DEPLOYER() internal view returns(address){
        return iVADER(VADER).DEPLOYER();
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
