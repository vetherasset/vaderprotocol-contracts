// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iPOOLS.sol";

    //======================================VADER=========================================//
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

    uint public repayDelay = 3600;

    address[] public arrayAnchors;
    uint[] public arrayPrices;

    mapping(address => mapping(address => uint)) public mapMemberToken_depositBase;
    mapping(address => mapping(address => uint)) public mapMemberToken_depositToken;
    mapping(address => mapping(address => uint)) public mapMemberToken_lastDeposited;

    event PoolReward(address indexed base, address indexed token, uint amount);
    event Protection(address indexed member, uint amount);
    event Curated(address indexed curator, address indexed token);

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
    }

    //=========================================DAO=========================================//
    // Can set params
    function setParams(uint _one, uint _two, uint _three) public onlyDAO {
        rewardReductionFactor = _one;
        timeForFullProtection = _two;
        curatedPoolLimit = _three;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(address base, uint inputBase, address token, uint inputToken) public returns(uint){
        uint _actualInputBase = moveTokenToPools(base, inputBase);
        uint _actualInputToken = moveTokenToPools(token, inputToken);
        addDepositData(msg.sender, token, _actualInputBase, _actualInputToken); 
        return iPOOLS(POOLS).addLiquidity(base, token, msg.sender);
    }

    function removeLiquidity(address base, address token, uint basisPoints) public returns (uint amountBase, uint amountToken) {
        (amountBase, amountToken) = iPOOLS(POOLS).removeLiquidity(base, token, basisPoints);
        address _member = msg.sender;
        uint _protection = getILProtection(_member, base, token, basisPoints);
        removeDepositData(_member, token, basisPoints, _protection); 
        iERC20(base).transfer(_member, _protection);
    }

      //=======================================SWAP===========================================//
    
    function swap(uint inputAmount, address inputToken, address outputToken) external returns (uint outputAmount){
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, 10000);
    }
    function swapWithLimit(uint inputAmount, address inputToken, address outputToken, uint slipLimit) external returns (uint outputAmount){
        return swapWithSynthsWithLimit(inputAmount, inputToken, false, outputToken, false, slipLimit);
    }

    function swapWithSynths(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth) external returns (uint outputAmount){
        return swapWithSynthsWithLimit(inputAmount, inputToken, inSynth, outputToken, outSynth, 10000);
    }

    function swapWithSynthsWithLimit(uint inputAmount, address inputToken, bool inSynth, address outputToken, bool outSynth, uint slipLimit) public returns (uint outputAmount){
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
            _handlePoolReward(_base, inputToken);
        } else if (isBase(inputToken)) {
            // BASE -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iPOOLS(POOLS).getBaseAmount(outputToken)) <= slipLimit);
            if(!outSynth){
                outputAmount = iPOOLS(POOLS).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS).mintSynth(_base, outputToken, _member);
            }
            _handlePoolReward(_base, outputToken);
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
            _handlePoolReward(_base, inputToken);
            _handlePoolReward(_base, outputToken);
        }
        _handleAnchorPriceUpdate(inputToken);
        _handleAnchorPriceUpdate(outputToken); 
        return outputAmount;
    }

        //====================================INCENTIVES========================================//
    
    function getRewardShare(address token) public view returns (uint rewardShare){
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
        return rewardShare;
    }

    function getReducedShare(uint amount) public view returns(uint){
        return iUTILS(UTILS()).calcShare(1, rewardReductionFactor, amount);
    }

    function _handlePoolReward(address _base, address _token) internal{
        uint _reward = getRewardShare(_token);
        iERC20(_base).transfer(POOLS, _reward);
        iPOOLS(POOLS).sync(_base, _token);
        emit PoolReward(_base, _token, _reward);
    }
    function pullIncentives(uint shareVADER, uint shareUSDV) public {
        iERC20(VADER).transferFrom(msg.sender, address(this), shareVADER);
        iERC20(USDV).transferFrom(msg.sender, address(this), shareUSDV);
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
        return protection;
    }

    function getProtection(address member, address token, uint basisPoints, uint coverage) public view returns(uint protection){
        if(isCurated(token)){
            uint _duration = block.timestamp - mapMemberToken_lastDeposited[member][token];
            if(_duration <= timeForFullProtection) {
                protection = iUTILS(UTILS()).calcShare(_duration, timeForFullProtection, coverage);
            } else {
                protection = coverage;
            }
        }
        return iUTILS(UTILS()).calcPart(basisPoints, protection);
    }
    function getCoverage(address member, address token) public view returns (uint){
        uint _B0 = mapMemberToken_depositBase[member][token]; uint _T0 = mapMemberToken_depositToken[member][token];
        uint _units = iPOOLS(POOLS).getMemberUnits(token, member);
        uint _B1 = iUTILS(UTILS()).calcShare(_units, iPOOLS(POOLS).getUnits(token), iPOOLS(POOLS).getBaseAmount(token));
        uint _T1 = iUTILS(UTILS()).calcShare(_units, iPOOLS(POOLS).getUnits(token), iPOOLS(POOLS).getTokenAmount(token));
        return iUTILS(UTILS()).calcCoverage(_B0, _T0, _B1, _T1);
    }

    //=====================================CURATION==========================================//

    function curatePool(address token) public {
        require(iPOOLS(POOLS).isAsset(token));
        if(!isCurated(token)){
            if(curatedPoolCount < curatedPoolLimit){
                _isCurated[token] = true;
                curatedPoolCount += 1;
            }
        }
        emit Curated(msg.sender, token);
    }
    function replacePool(address oldToken, address newToken) public {
        require(iPOOLS(POOLS).isAsset(newToken));
        if(iPOOLS(POOLS).getBaseAmount(newToken) > iPOOLS(POOLS).getBaseAmount(oldToken)){
            _isCurated[oldToken] = false;
            _isCurated[newToken] = true;
            emit Curated(msg.sender, newToken);
        }
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) public {
        require(arrayAnchors.length < 5);
        require(iPOOLS(POOLS).isAnchor(token));
        arrayAnchors.push(token);
        arrayPrices.push(iUTILS(UTILS()).calcValueInBase(token, one));
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) public {
        require(iPOOLS(POOLS).isAnchor(newToken), "Not anchor");
        require((iPOOLS(POOLS).getBaseAmount(newToken) > iPOOLS(POOLS).getBaseAmount(oldToken)), "Not deeper");
        _requirePriceBounds(oldToken, 500, false);                              // if price oldToken >5%
        _requirePriceBounds(newToken, 200, true);                               // if price newToken <2%
        // list/delist, add to arrayAnchors
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
        uint _lower = iUTILS(UTILS()).calcPart((_10k - bound), _targetPrice);
        uint _upper = (_targetPrice * (_10k + bound)) / _10k;
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
    function getAnchorPrice() public view returns (uint anchorPrice){
        if(arrayPrices.length > 0){
            uint[] memory _sortedAnchorFeed = _sortArray(arrayPrices);  // Sort price array
            anchorPrice = _sortedAnchorFeed[2];                         // Return the middle
        } else {
            anchorPrice = one;
        }
        return anchorPrice;
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
    // Draw debt for self
    function borrow(uint amount, address collateralAsset, address debtAsset) public returns (uint) {
        return borrowForMember(amount, collateralAsset, debtAsset, msg.sender);;
    }

    function borrowForMember(uint amount, address collateralAsset, address debtAsset, address member) public returns(uint debt) {
        (uint _collateral, uint _baseBorrow) = _handleTransferIn(amount, collateralAsset); // get collateral and valueinBase
        totalCollateral[_collateralAsset][_debtAsset] += _collateral;               // Record collateral 
        reserve -= _baseBorrow;                                                     // deduct from reserve
        debt = iUTILS(UTILS()).calcSwapValueInToken(debtAsset, _baseBorrow);        // get debt output
        totalDebt[_collateralAsset][_debtAsset] += debt;                            // Record debt
        _addDebtToMember(_collateral, collateralAsset, debt, debtAsset, member);    // Update member details
        iPOOLS(POOLS).swap(_baseBorrow, base, debtAsset, member);                   // Execute
        emit AddCollateral(amount, collateralAsset, debt, debtAsset);               // Event
    }

    // Repay for self
    function repay(uint amount, address collateralAsset, address debtAsset) public returns (uint){
        return repayForMember(amount, collateralAsset, debtAsset, msg.sender);;
    }
     // Repay for member
    function repayForMember(uint amount, address collateralAsset, address debtAsset, address member) public returns (uint collateralUnlocked){
        require(block.timestamp >= mapMember_Details[member].mapMember_Debt[collateralAsset].timeBorrowed[debtAsset] + repayDelay;   // min 1hr withdraw period 
        require(totalCollateral[collateralAsset][debtAsset] > 0, 'PURGED');
        require(totalDebt[collateralAsset][debtAsset] >= _amount, 'INPUTERR');
        uint _actualInputDebt = _handleTransferInDebt(debtAsset, _amount, _member);  // Get Debt
        totalDebt[_collateralAsset][_debtAsset] -= _actualInputDebt;                   // Update debt 
        reserve += iPOOLS(POOLS).swap();                                               // Swap Debt to Base back here
        uint _debtMember = mapMember_Details[member].mapCollateral_Debt[collateralAsset].debt[debtAsset]; // Outstanding Debt
        uint _collateralMember = mapMember_Details[member].mapCollateral_Debt[collateralAsset].collateral[debtAsset]; // Collateral
        collateralUnlocked = iUTILS(_DAO().UTILS()).calcShare(_actualInputDebt, _debtMember, _collateralMember); // Unlock collateral that is pro-rata to re-paid debt ($50/$100 = 50%)
        totalCollateral[_collateralAsset][_debtAsset] -= collateralUnlocked;               // Update collateral 
        _removeDebtForMember(collateralUnlocked, collateralAsset, _actualInputDebt, debtAsset, _member);  // Remove
        emit RemoveCollateral(_assetCollateralRemoved, debtAsset, actualInputAssetD);
        _sendFunds(_member, collateralAsset, collateralUnlocked);
        // if(totalDebt[collateralAsset][debtAsset] == 0){
        //     TimeLoaned[collateralAsset][debtAsset] = 0;
        // }
        emit RemoveCollateral(_assetCollateralRemoved, debtAsset, actualInputAssetD);
    }

    // function purgeMember() public {

    // }

    // function getInterestPayment() public {
        
    // }

    // function _addDebtToCDP(uint _collateral, address _collateralAsset, uint _debt, address _debtAsset) internal {
        
    // }

    function _handleTransferIn(uint256 _amount, address _collateralAsset) internal returns(uint256 _actual, uint _borrowedBase){
        uint _collateralAdjusted = _amount.mul(6666).div(10000); // 150% collateral Ratio
        if(_collateralAsset == BASE){
            _borrowedBase = _collateralAdjusted;
            _amount = getFunds(_collateralAsset, _amount); // Get funds
        }else if(isPool(_collateralAsset)){
             _borrowedBase = iUTILS(UTILS()).calcLiquidityValueBase(_collateralAsset, _collateralAdjusted); // calc units to BASE
             _amount = iPOOLS(POOLS).lockUnits(_amount, _collateralAsset, msg.sender); // Lock units to protocol
        }else if(isSynth()){
            _borrowedBase = iUTILS(UTILS()).calcSwapValueInBase(_collateralAsset, _collateralAdjusted); // Calc swap value
            _amount = getFunds(_collateralAsset, _amount); // Get synths
        }
        return (_amount, _borrowedBase);
    }
    function _handleTransferOut(address _collateralAsset, address _member, uint256 _amount) internal returns(uint256 _actual){
        if(_collateralAsset == BASE || isSynth()){
            sendFunds(_collateralAsset, _amount); // Send Base
        }else if(isPool(_collateralAsset)){
             iPOOLS(POOLS).unlockUnits(_amount, _collateralAsset, msg.sender); // Unlock units to protocol
        }
    }

    // #TODO: make FoT-safe
    function _getFunds(address _token, uint _amount) internal returns(uint _amount) {
        if(tx.origin==msg.sender){
            require(iERC20(_token).transferTo(address(this), _amount));
        }else{
            require(iERC20(_token).transferFrom(msg.sender, address(this), _amount));
        }
    }
    function sendFunds(address _token, address _member, uint _amount) internal {
        require(iERC20(_token).transfer(_member, _amount));
    }

    function _addDebtToMember(uint _collateral, address _collateralAsset, uint _debt, address _debtAsset, address _member) internal {
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] += _debt;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] += _collateral;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].timeBorrowed[_debtAsset] = block.timestamp;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].collateralDeposited[_debtAsset] += _collateral;
    }
    function _removeDebtFromMember(uint _collateral, address _collateralAsset, uint _debt, address _debtAsset, address _member) internal {
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].debt[_debtAsset] += _debt;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].collateral[_debtAsset] += _collateral;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].timeBorrowed[_debtAsset] = block.timestamp;
        mapMember_Details[_member].mapCollateral_Debt[_collateralAsset].collateralDeposited[_debtAsset] += _collateral;
    }



    //======================================HELPERS=========================================//

    function isBase(address token) public view returns(bool _isBase) {
        _isBase = false;
        if(token == VADER || token == USDV){
            _isBase = true;
        }
        return _isBase;
    }

    function reserveVADER() public view returns(uint){
        return iERC20(VADER).balanceOf(address(this));
    }
    function reserveUSDV() public view returns(uint){
        return iERC20(USDV).balanceOf(address(this));
    }

    // Safe transferFrom in case token charges transfer fees
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
        return safeAmount;
    }

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
    function isCurated(address token) public view returns(bool curated){
        if(_isCurated[token]){
            curated = true;
        } else if(iPOOLS(POOLS).isAnchor(token)){
            curated = true;
        }
        return curated;
    }
}