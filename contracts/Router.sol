// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iPOOLS.sol";
import "./iSYNTH.sol";

contract Router {

    // Parameters
    bool private inited;
    uint one = 10**18;
    uint _10k = 10000;
    uint public rewardReductionFactor;
    uint public timeForFullProtection;

    uint public curatedPoolLimit;
    uint public curatedPoolCount;
    mapping(address => bool) private _isCurated;
    
    address public VADER;
    address public USDV;
    address public POOLS;

    uint public anchorLimit;
    uint public insidePriceLimit;
    uint public outsidePriceLimit;
    address[] public arrayAnchors;
    uint[] public arrayPrices;

    uint public repayDelay = 3600;

    mapping(address => mapping(address => uint)) public mapMemberToken_depositBase;
    mapping(address => mapping(address => uint)) public mapMemberToken_depositToken;
    mapping(address => mapping(address => uint)) public mapMemberToken_lastDeposited;

    mapping(address => CollateralDetails) private mapMember_Collateral;
    mapping(address => mapping(address => uint)) public mapCollateralDebt_Collateral;
    mapping(address => mapping(address => uint)) public mapCollateralDebt_Debt;
    mapping(address => mapping(address => uint)) public mapCollateralDebt_interestPaid;

    struct CollateralDetails {
        uint ID;
        mapping(address => DebtDetails) mapCollateral_Debt;
    }
    struct DebtDetails{
        uint ID;
        mapping(address =>uint) debt; //assetC > AssetD > AmountDebt
        mapping(address =>uint) collateral; //assetC > AssetD > AmountCol
        // mapping(address =>uint) assetCollateralDeposit; //assetC > AssetD > AmountCol
        // mapping(address =>uint) timeBorrowed; // assetC > AssetD > time
        // mapping(address =>uint) currentDay; // assetC > AssetD > time
    }

    event PoolReward(address indexed base, address indexed token, uint amount);
    event Protection(address indexed member, uint amount);
    event Curated(address indexed curator, address indexed token);

    event AddCollateral(address indexed member, address indexed collateralAsset, uint collateralLocked, address indexed debtAsset, uint debtIssued);
    event RemoveCollateral(address indexed member, address indexed collateralAsset, uint collateralUnlocked, address indexed debtAsset, uint debtReturned);

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO(), "Not DAO");
        _;
    }

    //=====================================CREATION=========================================//
    // Constructor
    constructor() {}
    // Init
    function init(address _vader, address _usdv, address _pool) public {
        require(inited == false,  "inited");
        inited = true;
        VADER = _vader;
        USDV = _usdv;
        POOLS = _pool;
        rewardReductionFactor = 1;
        timeForFullProtection = 1;//8640000; //100 days
        curatedPoolLimit = 1;
        anchorLimit = 5;
        insidePriceLimit = 200;
        outsidePriceLimit = 500;
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint newFactor, uint newTime, uint newLimit) external onlyDAO {
        rewardReductionFactor = newFactor;
        timeForFullProtection = newTime;
        curatedPoolLimit = newLimit;
    }
    function setAnchorParams(uint newLimit, uint newInside, uint newOutside) external onlyDAO {
        anchorLimit = newLimit;
        insidePriceLimit = newInside;
        outsidePriceLimit = newOutside;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, uint inputBase, address token, uint inputToken) external returns(uint){
        uint _actualInputBase = moveTokenToPools(base, inputBase);
        uint _actualInputToken = moveTokenToPools(token, inputToken);
        addDepositData(msg.sender, token, _actualInputBase, _actualInputToken); 
        return iPOOLS(POOLS).addLiquidity(base, token, msg.sender);
    }

    function removeLiquidity(address base, address token, uint basisPoints) external returns (uint amountBase, uint amountToken) {
        (amountBase, amountToken) = iPOOLS(POOLS).removeLiquidity(base, token, basisPoints);
        uint _protection = getILProtection(msg.sender, base, token, basisPoints);
        removeDepositData(msg.sender, token, basisPoints, _protection); 
        iERC20(base).transfer(msg.sender, _protection);
    }

      //=======================================SWAP===========================================//
    
    function swap(uint inputAmount, address inputToken, address outputToken) external returns (uint outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, 10000);
    }
    function swapWithLimit(uint inputAmount, address inputToken, address outputToken, uint slipLimit) external returns (uint outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, slipLimit);
    }

    function swapWithSynths(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth) external returns (uint outputAmount) {
        return swapWithSynthsWithLimit(inputAmount, inputToken, inSynth, outputToken, outSynth, 10000);
    }

    function swapWithSynthsWithLimit(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth, uint slipLimit) public returns (uint outputAmount) {
        address _member = msg.sender;
        if(!inSynth){
            moveTokenToPools(inputToken, inputAmount);
        } else {
            moveTokenToPools(iPOOLS(POOLS).getSynth(inputToken), inputAmount);
        }
        address _base;
        if(iPOOLS(POOLS).isAnchor(inputToken) || iPOOLS(POOLS).isAnchor(outputToken)) {
            _base = VADER;
        } else {
            _base = USDV;
        }
        if (isBase(outputToken)) {
            // Token||Synth -> BASE
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS).getTokenAmount(inputToken)) <= slipLimit);
            if(!inSynth){
                outputAmount = iPOOLS(POOLS).swap(_base, inputToken, _member, true);
            } else {
                outputAmount = iPOOLS(POOLS).burnSynth(_base, inputToken, _member);
            }
        } else if (isBase(inputToken)) {
            // BASE -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS).getBaseAmount(outputToken)) <= slipLimit);
            if(!outSynth){
                outputAmount = iPOOLS(POOLS).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS).mintSynth(_base, outputToken, _member);
            }
        } else if (!isBase(inputToken) && !isBase(outputToken)) {
            // Token||Synth -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS).getTokenAmount(inputToken)) <= slipLimit);
            if(!inSynth){
                iPOOLS(POOLS).swap(_base, inputToken, POOLS, true);
            } else {
                iPOOLS(POOLS).burnSynth(_base, inputToken, POOLS);
            }
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS).getBaseAmount(outputToken)) <= slipLimit);
            if(!outSynth){
                outputAmount = iPOOLS(POOLS).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS).mintSynth(_base, outputToken, _member);
            }
        }
        _handlePoolReward(_base, inputToken);
        _handlePoolReward(_base, outputToken);
        _handleAnchorPriceUpdate(inputToken);
        _handleAnchorPriceUpdate(outputToken); 
    }

        //====================================INCENTIVES========================================//
    
    function getRewardShare(address token) public view returns (uint rewardShare) {
        if(emitting() && isCurated(token)){
            uint _baseAmount = iPOOLS(POOLS).getBaseAmount(token);
            if (iPOOLS(POOLS).isAsset(token)) {
                uint _share = iUTILS(UTILS()).calcShare(_baseAmount, iPOOLS(POOLS).pooledUSDV(), reserveUSDV());
                rewardShare = getReducedShare(_share);
            } else if(iPOOLS(POOLS).isAnchor(token)) {
                uint _share = iUTILS(UTILS()).calcShare(_baseAmount, iPOOLS(POOLS).pooledVADER(), reserveVADER());
                rewardShare = getReducedShare(_share);
            }
        }
    }

    function getReducedShare(uint amount) public view returns(uint) {
        return iUTILS(UTILS()).calcShare(1, rewardReductionFactor, amount); // Reduce to stop depleting fast
    }

    function _handlePoolReward(address _base, address _token) internal{
        if(!isBase(_token)){                        // USDV or VADER is never a pool
            uint _reward = getRewardShare(_token);
            iERC20(_base).transfer(POOLS, _reward);
            iPOOLS(POOLS).sync(_base, _token);
            emit PoolReward(_base, _token, _reward);
        }
    }

    //=================================IMPERMANENT LOSS=====================================//
    
    function addDepositData(address member, address token, uint amountBase, uint amountToken) internal {
        mapMemberToken_depositBase[member][token] += amountBase;
        mapMemberToken_depositToken[member][token] += amountToken;
        mapMemberToken_lastDeposited[member][token] = block.timestamp;
    }
    function removeDepositData(address member, address token, uint basisPoints, uint protection) internal {
        mapMemberToken_depositBase[member][token] += protection;
        uint _baseToRemove = iUTILS(UTILS()).calcPart(basisPoints, mapMemberToken_depositBase[member][token]);
        uint _tokenToRemove = iUTILS(UTILS()).calcPart(basisPoints, mapMemberToken_depositToken[member][token]);
        mapMemberToken_depositBase[member][token] -= _baseToRemove;
        mapMemberToken_depositToken[member][token] -= _tokenToRemove;
    }

    function getILProtection(address member, address base, address token, uint basisPoints) public view returns(uint protection) {
        protection = getProtection(member, token, basisPoints, getCoverage(member, token));
        if(base == VADER){
            if(protection >= reserveVADER()){
                protection = reserveVADER(); // In case reserve is running out
            }
        } else {
            if(protection >= reserveUSDV()){
                protection = reserveUSDV(); // In case reserve is running out
            }
        }
    }
    
    // Actual protection with 100 day rule and Reserve balance
    function getProtection(address member, address token, uint basisPoints, uint coverage) public view returns(uint protection) {
        if(isCurated(token)){
            uint _duration = block.timestamp - mapMemberToken_lastDeposited[member][token];
            if(_duration <= timeForFullProtection) {
                protection = iUTILS(UTILS()).calcShare(_duration, timeForFullProtection, coverage); // Apply 100 day rule
            } else {
                protection = coverage;
            }
        }
        return iUTILS(UTILS()).calcPart(basisPoints, protection);
    }
    // Theoretical coverage based on deposit/redemption values
    function getCoverage(address member, address token) public view returns (uint) {
        uint _B0 = mapMemberToken_depositBase[member][token]; uint _T0 = mapMemberToken_depositToken[member][token];
        uint _units = iPOOLS(POOLS).getMemberUnits(token, member);
        uint _B1 = iUTILS(UTILS()).calcShare(_units, iPOOLS(POOLS).getUnits(token), iPOOLS(POOLS).getBaseAmount(token));
        uint _T1 = iUTILS(UTILS()).calcShare(_units, iPOOLS(POOLS).getUnits(token), iPOOLS(POOLS).getTokenAmount(token));
        return iUTILS(UTILS()).calcCoverage(_B0, _T0, _B1, _T1);
    }

    //=====================================CURATION==========================================//

    function curatePool(address token) external {
        require(iPOOLS(POOLS).isAsset(token) || iPOOLS(POOLS).isAnchor(token));
        if(!isCurated(token)){
            if(curatedPoolCount < curatedPoolLimit){ // Limit
                _isCurated[token] = true;
                curatedPoolCount += 1;
            }
        }
        emit Curated(msg.sender, token);
    }
    function replacePool(address oldToken, address newToken) external {
        require(iPOOLS(POOLS).isAsset(newToken));
        if(iPOOLS(POOLS).getBaseAmount(newToken) > iPOOLS(POOLS).getBaseAmount(oldToken)){ // Must be deeper
            _isCurated[oldToken] = false;
            _isCurated[newToken] = true;
            emit Curated(msg.sender, newToken);
        }
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) external {
        require(arrayAnchors.length < anchorLimit); // Limit
        require(iPOOLS(POOLS).isAnchor(token));     // Must be anchor
        arrayAnchors.push(token);                   // Add
        arrayPrices.push(iUTILS(UTILS()).calcValueInBase(token, one));
        _isCurated[token] = true; 
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) external {
        require(iPOOLS(POOLS).isAnchor(newToken), "Not anchor");
        require((iPOOLS(POOLS).getBaseAmount(newToken) > iPOOLS(POOLS).getBaseAmount(oldToken)), "Not deeper");
        _requirePriceBounds(oldToken, outsidePriceLimit, false);                             // if price oldToken >5%
        _requirePriceBounds(newToken, insidePriceLimit, true);                               // if price newToken <2%
        _isCurated[oldToken] = false; 
        _isCurated[newToken] = true; 
        for(uint i = 0; i<arrayAnchors.length; i++){
            if(arrayAnchors[i] == oldToken){
                arrayAnchors[i] = newToken;
            }
        }
        updateAnchorPrice(newToken);
    }

    function _requirePriceBounds(address token, uint bound, bool inside) internal view {
        uint _targetPrice = getAnchorPrice();
        uint _testingPrice = iUTILS(UTILS()).calcValueInBase(token, one);
        uint _lower = iUTILS(UTILS()).calcPart((_10k - bound), _targetPrice);   // ie 98% of price
        uint _upper = (_targetPrice * (_10k + bound)) / _10k;                   // ie 105% of price
        if(inside){
            require((_testingPrice >= _lower && _testingPrice <= _upper), "Not inside");
        } else {
            require((_testingPrice <= _lower || _testingPrice >= _upper), "Not outside");
        }
    }

    // Anyone to update prices
    function updateAnchorPrice(address token) public {
        for(uint i = 0; i<arrayAnchors.length; i++){
            if(arrayAnchors[i] == token){
                arrayPrices[i] = iUTILS(UTILS()).calcValueInBase(arrayAnchors[i], one);
            }
        }
    }

    function _handleAnchorPriceUpdate(address _token) internal{
        if(iPOOLS(POOLS).isAnchor(_token)){
            updateAnchorPrice(_token);
        }
    }

    // Price of 1 VADER in USD
    function getAnchorPrice() public view returns (uint anchorPrice) {
        if(arrayPrices.length > 0){
            uint[] memory _sortedAnchorFeed = _sortArray(arrayPrices);  // Sort price array, no need to modify storage
            anchorPrice = _sortedAnchorFeed[2];                         // Return the middle
        } else {
            anchorPrice = one;          // Edge case for first USDV mint
        }
    }

    // The correct amount of Vader for an input of USDV
    function getVADERAmount(uint USDVAmount) public view returns (uint vaderAmount){
        uint _price = getAnchorPrice();
        return (_price * USDVAmount) / one;
    }

    // The correct amount of USDV for an input of VADER
    function getUSDVAmount(uint vaderAmount) public view returns (uint USDVAmount){
        uint _price = getAnchorPrice();
        return (vaderAmount * one) / _price;
    }
    
    
    //======================================LENDING=========================================//
    // // Lock collateral
    // function borrow(uint amount, address collateralAsset) public returns (uint) {
    //     return lockForMember(amount, collateralAsset, msg.sender);
    // }
    // function lockForMember(uint amount, address collateralAsset, address member) public returns(uint inputAmount) {
    //     inputAmount = _handleTransferIn(member, collateralAsset, amount); // get collateral and valueinBase
    //     mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] += _collateral;
    // }

    // Draw debt for self
    function borrow(uint amount, address collateralAsset, address debtAsset) public returns (uint) {
        return borrowForMember(msg.sender, amount, collateralAsset, debtAsset);
    }

    function borrowForMember(address member, uint amount, address collateralAsset, address debtAsset) public returns(uint) {
        assetChecks(collateralAsset, debtAsset);
        uint _collateral = _handleTransferIn(member, collateralAsset, amount);                  // get collateral 
        (uint _debtIssued, uint _baseBorrowed) = getCollateralValueInBase(member, _collateral, collateralAsset, debtAsset);
        mapCollateralDebt_Collateral[collateralAsset][debtAsset] += _collateral;               // Record collateral 
        mapCollateralDebt_Debt[collateralAsset][debtAsset] += _debtIssued;                            // Record debt
        _addDebtToMember(member, _collateral, collateralAsset, _debtIssued, debtAsset);    // Update member details
        if(collateralAsset == VADER || iPOOLS(POOLS).isAnchor(debtAsset)){
            iERC20(VADER).transfer(POOLS, _baseBorrowed);                                  // Send to pools
            iPOOLS(POOLS).swap(VADER, debtAsset, member, false);                         // Execute swap to member
        } else if(collateralAsset == USDV || iPOOLS(POOLS).isAsset(debtAsset)) {
            iERC20(USDV).transfer(POOLS, _baseBorrowed);                                  // Send to pools
            iPOOLS(POOLS).swap(USDV, debtAsset, member, false);                         // Execute swap to member
        }
        emit AddCollateral(member, collateralAsset, amount, debtAsset, _debtIssued);               // Event
        return _debtIssued;
    }

    // Repay for self
    function repay(uint amount, address collateralAsset, address debtAsset) public returns (uint){
        return repayForMember(msg.sender, amount, collateralAsset, debtAsset);
    }
     // Repay for member
    function repayForMember(address member, uint basisPoints, address collateralAsset, address debtAsset) public returns (uint collateralUnlocked){
        // require(block.timestamp >= mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].timeBorrowed[debtAsset] + repayDelay);   // min 1hr withdraw period 
        // require(mapCollateralDebt_Collateral[collateralAsset][debtAsset] > 0, 'PURGED');
        // require(mapCollateralDebt_Debt[collateralAsset][debtAsset] >= amount, 'INPUT-ERR');
        uint _amount = iUTILS(UTILS()).calcPart(basisPoints, getMemberDebt(member, collateralAsset, debtAsset));
        uint _debt = moveTokenToPools(debtAsset, _amount);    // Get Debt
        if(collateralAsset == VADER || iPOOLS(POOLS).isAnchor(debtAsset)){
            iPOOLS(POOLS).swap(VADER, debtAsset, address(this), true);           // Swap Debt to Base back here
        } else if(collateralAsset == USDV || iPOOLS(POOLS).isAsset(debtAsset)) {
            iPOOLS(POOLS).swap(USDV, debtAsset, address(this), true);           // Swap Debt to Base back here
        }
        collateralUnlocked = getDebtValueInCollateral(member, _debt, collateralAsset, debtAsset); // Unlock collateral that is pro-rata to re-paid debt ($50/$100 = 50%)
        mapCollateralDebt_Collateral[collateralAsset][debtAsset] -= collateralUnlocked;               // Update collateral 
        mapCollateralDebt_Debt[collateralAsset][debtAsset] -= _debt;                   // Update debt 
        _removeDebtFromMember(member, collateralUnlocked, collateralAsset, _debt, debtAsset);  // Remove
        emit RemoveCollateral(member, collateralAsset, collateralUnlocked, debtAsset, _debt);
        _handleTransferOut(member, collateralAsset, collateralUnlocked);
        // if(totalDebt[collateralAsset][debtAsset] == 0){
        //     TimeLoaned[collateralAsset][debtAsset] = 0;
        // }
    }

    // Called once a day to pay interest
    function _payInterest(address collateralAsset, address debtAsset) internal {
        uint _interestOwed = getInterestOwed(collateralAsset, debtAsset);
        mapCollateralDebt_interestPaid[collateralAsset][debtAsset] += _interestOwed;
        // _removeFromCollateral();
        if(isBase(collateralAsset)){
            iERC20(collateralAsset).transfer(POOLS, _interestOwed);
            iPOOLS(POOLS).sync(collateralAsset, debtAsset);
        } else if(iPOOLS(POOLS).isSynth(collateralAsset)){
            iERC20(collateralAsset).transfer(POOLS, _interestOwed);
            iPOOLS(POOLS).syncSynth(iSYNTH(collateralAsset).TOKEN());
        }
    }
    // Gets in
    function getInterestOwed(address collateralAsset, address debtAsset) public returns(uint interestOwed) {
        uint _interestPayment = getInterestPayment(collateralAsset, debtAsset);
        if(isBase(collateralAsset)){
            interestOwed = iUTILS(UTILS()).calcValueInBase(debtAsset, _interestPayment); // Back to base
        } else if(iPOOLS(POOLS).isSynth(collateralAsset)) {
            interestOwed = iUTILS(UTILS()).calcValueOfTokenInToken(debtAsset, _interestPayment, collateralAsset); // Get value of Synth in debtAsset (doubleSwap)
        }
    }
    function getInterestPayment(address collateralAsset, address debtAsset) public view returns(uint) {
        uint _debtLoading = getDebtLoading(collateralAsset, debtAsset);
        return _debtLoading * mapCollateralDebt_Debt[collateralAsset][debtAsset]; 
    }
    function getDebtLoading(address collateralAsset, address debtAsset) public view returns(uint) {
        uint _debtIssued = mapCollateralDebt_Debt[collateralAsset][debtAsset];
        uint _debtDepth = iPOOLS(POOLS).getTokenAmount(debtAsset);
        return (_debtIssued * 10000) / _debtDepth; 
    }

    function checkLiquidate() public {
        // get member remaining Collateral: originalDeposit - shareOfInterestPayments
        // if remainingCollateral <= 101% * debtValueInCollateral
        // purge, send remaining collateral to liquidator
    }

    // function _addDebtToCDP(uint _collateral, address _collateralAsset, uint _debt, address _debtAsset) internal {
        
    // }

    // function purgeMember() public {

    // }

    function assetChecks(address collateralAsset, address debtAsset) public{
        if(collateralAsset == VADER){
            require(iPOOLS(POOLS).isAnchor(debtAsset), "Bad Combo"); // Can borrow Anchor with VADER/ANCHOR-SYNTH
        } else if(collateralAsset == USDV){
            require(iPOOLS(POOLS).isAsset(debtAsset), "Bad Combo"); // Can borrow Asset with VADER/ASSET-SYNTH
        } else if(iPOOLS(POOLS).isSynth(collateralAsset) && iPOOLS(POOLS).isAnchor(iSYNTH(collateralAsset).TOKEN())){
            require(iPOOLS(POOLS).isAnchor(debtAsset), "Bad Combo"); // Can borrow Anchor with VADER/ANCHOR-SYNTH
        } else if(iPOOLS(POOLS).isSynth(collateralAsset) && iPOOLS(POOLS).isAsset(iSYNTH(collateralAsset).TOKEN())){
            require(iPOOLS(POOLS).isAsset(debtAsset), "Bad Combo"); // Can borrow Anchor with VADER/ANCHOR-SYNTH
        }
    }

    // Get Collateral
    function _handleTransferIn(address _member, address _collateralAsset, uint _amount) internal returns(uint _inputAmount){
        if(isBase(_collateralAsset) || iPOOLS(POOLS).isSynth(_collateralAsset)){
            _inputAmount = _getFunds(_collateralAsset, _amount); // Get funds
        }else if(isPool(_collateralAsset)){
             iPOOLS(POOLS).lockUnits(_amount, _collateralAsset, _member); // Lock units to protocol
             _inputAmount = _amount;
        }
    }
    // Send Collateral
    function _handleTransferOut(address _member, address _collateralAsset, uint _amount) internal{
        if(isBase(_collateralAsset) || iPOOLS(POOLS).isSynth(_collateralAsset)){
            _sendFunds(_collateralAsset, _member, _amount); // Send Base
        }else if(isPool(_collateralAsset)){
            iPOOLS(POOLS).unlockUnits(_amount, _collateralAsset, _member); // Unlock units to member
        }
    }

    function _getFunds(address _token, uint _amount) internal returns(uint) {
        uint _balance = iERC20(_token).balanceOf(address(this));
        if(tx.origin==msg.sender){
            require(iERC20(_token).transferTo(address(this), _amount));
        }else{
            require(iERC20(_token).transferFrom(msg.sender, address(this), _amount));
        }
        return iERC20(_token).balanceOf(address(this)) - _balance;
    }

    function _sendFunds(address _token, address _member, uint _amount) internal {
        require(iERC20(_token).transfer(_member, _amount));
    }

    function getCollateralValueInBase(address member, uint collateral, address collateralAsset, address debtAsset) public returns (uint debt, uint baseValue){
        uint _collateralAdjusted = (collateral * 6666) / 10000; // 150% collateral Ratio
        if(isBase(collateralAsset)){
            baseValue = _collateralAdjusted;
        }else if(isPool(collateralAsset)){
            baseValue = iUTILS(UTILS()).calcAsymmetricShare(_collateralAdjusted, iPOOLS(POOLS).getMemberUnits(collateralAsset, member), iPOOLS(POOLS).getBaseAmount(collateralAsset)); // calc units to BASE
        }else if(iPOOLS(POOLS).isSynth(collateralAsset)){
            baseValue = iUTILS(UTILS()).calcSwapValueInBase(iSYNTH(collateralAsset).TOKEN(), _collateralAdjusted); // Calc swap value
        }
        debt = iUTILS(UTILS()).calcSwapValueInToken(debtAsset, baseValue);        // get debt output
        return (debt, baseValue);
    }

    function getDebtValueInCollateral(address member, uint debt, address collateralAsset, address debtAsset) public view returns(uint){
        uint _debtMember = mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].debt[debtAsset]; // Outstanding Debt
        uint _collateralMember = mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].collateral[debtAsset]; // Collateral
        return iUTILS(UTILS()).calcShare(debt, _debtMember, _collateralMember); 
    }

    function _addDebtToMember(address _member, uint _collateral, address _collateralAsset, uint _debt, address _debtAsset) internal {
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] += _debt;
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] += _collateral;
        // mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].timeBorrowed[_debtAsset] = block.timestamp;
        // mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateralDeposited[_debtAsset] -= _collateral;
    }
    function _removeDebtFromMember(address _member, uint _collateral, address _collateralAsset, uint _debt, address _debtAsset) internal {
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] -= _debt;
        mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] -= _collateral;
        // mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].timeBorrowed[_debtAsset] = block.timestamp;
        // mapMember_Collateral[_member].mapCollateral_Debt[_collateralAsset].collateralDeposited[_debtAsset] += _collateral;
    }



    //======================================HELPERS=========================================//

    function isBase(address token) public view returns(bool base) {
        if(token == VADER || token == USDV){
            return true;
        }
    }

    function reserveVADER() public view returns(uint) {
        return iERC20(VADER).balanceOf(address(this));
    }
    function reserveUSDV() public view returns(uint) {
        return iERC20(USDV).balanceOf(address(this));
    }

    // Optionality
    function moveTokenToPools(address _token, uint _amount) internal returns(uint safeAmount) {
        if(_token == VADER || _token == USDV || iPOOLS(POOLS).isSynth(_token)){
            safeAmount = _amount;
            if(tx.origin==msg.sender){
                iERC20(_token).transferTo(POOLS, _amount);
            }else{
                iERC20(_token).transferFrom(msg.sender, POOLS, _amount);
            }
        } else {
            uint _startBal = iERC20(_token).balanceOf(POOLS);
            iERC20(_token).transferFrom(msg.sender, POOLS, _amount);
            safeAmount = iERC20(_token).balanceOf(POOLS) - _startBal;
        }
    }

    // Sorts array in memory from low to high, returns in-memory (Does not need to modify storage)
    function _sortArray(uint[] memory array) internal pure returns (uint[] memory){
        uint l = array.length;
        for(uint i = 0; i < l; i++){
            for(uint j = i+1; j < l; j++){
                if(array[i] > array[j]){
                    uint temp = array[i];
                    array[i] = array[j];
                    array[j] = temp;
                }
            }
        }
        return array;
    }

    function UTILS() public view returns(address){
        return iVADER(VADER).UTILS();
    }
    function DAO() public view returns(address){
        return iVADER(VADER).DAO();
    }
    function emitting() public view returns(bool){
        return iVADER(VADER).emitting();
    }
    function isCurated(address token) public view returns(bool curated) {
        if(_isCurated[token]){
            curated = true;
        }
    }
    function isPool(address token) public view returns(bool pool) {
        if(iPOOLS(POOLS).isAnchor(token) || iPOOLS(POOLS).isAsset(token)){
            pool = true;
        }
    }
    function getMemberCollateral(address member, address collateralAsset, address debtAsset) external view returns(uint) {
        return mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].collateral[debtAsset];
    }
    function getMemberDebt(address member, address collateralAsset, address debtAsset) public view returns(uint) {
        return mapMember_Collateral[member].mapCollateral_Debt[collateralAsset].debt[debtAsset];
    }
    
}