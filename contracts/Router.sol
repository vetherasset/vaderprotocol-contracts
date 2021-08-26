// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/SafeERC20.sol";
import "./interfaces/iERC20.sol";
import "./interfaces/iGovernorAlpha.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iSYNTH.sol";
import "./interfaces/iFACTORY.sol";

contract Router {
    using SafeERC20 for ExternalERC20;

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

    uint256 public intervalTWAP;
    uint256 public accumulatedPrice;
    uint256 public lastUpdatedTime;
    uint256 public startIntervalAccumulatedPrice;
    uint256 public startIntervalTime;
    uint256 public cachedIntervalAccumulatedPrice;
    uint256 public cachedIntervalTime;

    mapping(address => mapping(address => uint256)) public mapMemberToken_depositBase;
    mapping(address => mapping(address => uint256)) public mapMemberToken_depositToken;
    mapping(address => mapping(address => uint256)) public mapMemberToken_lastDeposited;

    event PoolReward(address indexed base, address indexed token, uint256 amount);
    event Curated(address indexed curator, address indexed token);

    // Only TIMELOCK can execute
    modifier onlyTIMELOCK() {
        require(msg.sender == TIMELOCK(), "!TIMELOCK");
        _;
    }

    //=====================================CREATION=========================================//

    constructor(address _vader) {
        VADER = _vader;
        rewardReductionFactor = 1;
        timeForFullProtection = 1; //8640000; //100 days
        curatedPoolLimit = 1;
        intervalTWAP = 3; //6hours
        
        anchorLimit = 5;
        insidePriceLimit = 200;
        outsidePriceLimit = 500;
        
        lastUpdatedTime = block.timestamp;
        startIntervalTime = lastUpdatedTime;
        cachedIntervalTime = startIntervalTime;
    }

    //====================================== TIMELOCK =====================================//
    // Can set params
    function setParams(
        uint256 newFactor,
        uint256 newTime,
        uint256 newLimit,
        uint256 newInterval
    ) external onlyTIMELOCK {
        rewardReductionFactor = newFactor;
        timeForFullProtection = newTime;
        curatedPoolLimit = newLimit;
        intervalTWAP = newInterval;
    }

    function setAnchorParams(
        uint256 newLimit,
        uint256 newInside,
        uint256 newOutside
    ) external onlyTIMELOCK {
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
        address _member = msg.sender;
        addDepositData(_member, token, _actualInputBase, _actualInputToken);
        updateTWAPPrice();
        return iPOOLS(POOLS()).addLiquidity(base, _actualInputBase, token, _actualInputToken, _member);
    }

    function removeLiquidity(
        address base,
        address token,
        uint256 basisPoints
    ) external returns (uint256 units, uint256 amountBase, uint256 amountToken) {
        address _member = msg.sender;
        uint256 _protection = getILProtection(_member, base, token, basisPoints);
        if (_protection > 0) {
            uint256 _actualInputBase = iRESERVE(RESERVE()).requestFunds(base, POOLS(), _protection);
            iPOOLS(POOLS()).addLiquidity(base, _actualInputBase, token, 0, _member);
            mapMemberToken_depositBase[_member][token] += _protection;
        }
        (units, amountBase, amountToken) = iPOOLS(POOLS()).removeLiquidity(base, token, basisPoints, _member);
        removeDepositData(_member, token, basisPoints, _protection);
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
        updateTWAPPrice();
        address _member = msg.sender;
        uint256 movedAmount;
        if (!inSynth) {
            movedAmount = moveTokenToPools(inputToken, inputAmount);
        } else {
            movedAmount = moveTokenToPools(iPOOLS(POOLS()).getSynth(inputToken), inputAmount);
        }
        address _base;
        if (iPOOLS(POOLS()).isAnchor(inputToken) || iPOOLS(POOLS()).isAnchor(outputToken)) {
            _base = VADER;
        } else {
            _base = USDV();
        }
        if (isBase(outputToken)) {
            // Token||Synth -> BASE
            require(iUTILS(UTILS()).calcSwapSlip(movedAmount, iPOOLS(POOLS()).getTokenAmount(inputToken)) <= slipLimit, ">slipLimit");
            if (!inSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, inputToken, movedAmount, _member, true);
            } else {
                outputAmount = iPOOLS(POOLS()).burnSynth(inputToken, _member);
            }
        } else if (isBase(inputToken)) {
            // BASE -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(movedAmount, iPOOLS(POOLS()).getBaseAmount(outputToken)) <= slipLimit, ">slipLimit");
            if (!outSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, outputToken, movedAmount, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS()).mintSynth(outputToken, movedAmount, _member);
            }
        } else {
            // !isBase(inputToken) && !isBase(outputToken)
            // Token||Synth -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(movedAmount, iPOOLS(POOLS()).getTokenAmount(inputToken)) <= slipLimit, ">slipLimit");
            uint _intermediaryAmount;
            if (!inSynth) {
                _intermediaryAmount = iPOOLS(POOLS()).swap(_base, inputToken, movedAmount, POOLS(), true);
            } else {
                _intermediaryAmount = iPOOLS(POOLS()).burnSynth(inputToken, POOLS());
            }
            require(iUTILS(UTILS()).calcSwapSlip(_intermediaryAmount, iPOOLS(POOLS()).getBaseAmount(outputToken)) <= slipLimit, ">slipLimit");
            if (!outSynth) {
                outputAmount = iPOOLS(POOLS()).swap(_base, outputToken, _intermediaryAmount, _member, false);
            } else {
                outputAmount = iPOOLS(POOLS()).mintSynth(outputToken, _intermediaryAmount, _member);
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
            uint256 _actualInputBase = iRESERVE(RESERVE()).requestFunds(_base, POOLS(), _reward);
            iPOOLS(POOLS()).sync(_base, _actualInputBase, _token);
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

    function curatePool(address token) external onlyTIMELOCK {
        require(iPOOLS(POOLS()).isAsset(token) || iPOOLS(POOLS()).isAnchor(token), "!Asset && !Anchor");
        if (!isCurated(token)) {
            if (curatedPoolCount < curatedPoolLimit) {
                // Limit
                _isCurated[token] = true;
                curatedPoolCount += 1;
            }
        }
        emit Curated(msg.sender, token);
    }

    function replacePool(address oldToken, address newToken) external onlyTIMELOCK {
        require(iPOOLS(POOLS()).isAsset(newToken) || iPOOLS(POOLS()).isAnchor(newToken));
        _isCurated[oldToken] = false;
        _isCurated[newToken] = true;
        emit Curated(msg.sender, newToken);
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) external {
        require(arrayAnchors.length < anchorLimit, ">=Limit"); // Limit
        require(iPOOLS(POOLS()).isAnchor(token), "!Anchor"); // Must be anchor
        require(!iFACTORY(FACTORY()).isSynth(token), "Synth!"); // Must not be synth
        arrayAnchors.push(token); // Add
        mapAnchorAddress_arrayAnchorsIndex1[token] = arrayAnchors.length; // Store 1-based index
        arrayPrices.push(iUTILS(UTILS()).calcValueInBase(token, one));
        _isCurated[token] = true;
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) external onlyTIMELOCK {
        require(newToken != oldToken, "New token not new");
        uint idx1 = mapAnchorAddress_arrayAnchorsIndex1[oldToken];
        require(idx1 != 0, "No such old token");
        require(iPOOLS(POOLS()).isAnchor(newToken), "!Anchor"); // Must be anchor
        require(!iFACTORY(FACTORY()).isSynth(newToken), "Synth!"); // Must not be synth
        iUTILS(UTILS()).requirePriceBounds(newToken, insidePriceLimit, true, getAnchorPrice()); // if price newToken <2%
        _isCurated[oldToken] = false;
        _isCurated[newToken] = true;
        arrayAnchors[idx1 - 1] = newToken;
        updateAnchorPrice(newToken);
    }

    function _handleAnchorPriceUpdate(address _token) internal {
        if (iPOOLS(POOLS()).isAnchor(_token)) {
            updateAnchorPrice(_token);
        }
    }

    // Anyone to update prices
    function updateAnchorPrice(address token) public {
        uint idx1 = mapAnchorAddress_arrayAnchorsIndex1[token];
        if (idx1 != 0) {
            arrayPrices[idx1 - 1] = iUTILS(UTILS()).calcValueInBase(token, one);
        }
    }

    function updateTWAPPrice() public {
        uint _now = block.timestamp;
        uint _secondsSinceLastUpdate = _now - lastUpdatedTime;
        accumulatedPrice += _secondsSinceLastUpdate * getAnchorPrice();
        lastUpdatedTime = _now;
        if ((_now - cachedIntervalTime) > intervalTWAP) {
            // More than the interval, update interval params
            startIntervalAccumulatedPrice = cachedIntervalAccumulatedPrice; // update price from cache
            startIntervalTime = cachedIntervalTime; // update time from cache
            cachedIntervalAccumulatedPrice = accumulatedPrice; // reset cache
            cachedIntervalTime = _now; // reset cache
        }
    }

    // Price of 1 VADER in USD
    function getAnchorPrice() public view returns (uint256 anchorPrice) {
        // if array len odd  3/2 = 1; 5/2 = 2
        // if array len even 2/2 = 1; 4/2 = 2
        uint _anchorMiddle = arrayPrices.length / 2;
        uint256[] memory _sortedAnchorFeed = iUTILS(UTILS()).sortArray(arrayPrices); // Sort price array, no need to modify storage
        if (arrayPrices.length == 0) {
            anchorPrice = one; // Edge case for first USDV mint
        } else if (arrayPrices.length & 0x1 == 0x1) {
            // arrayPrices.length is odd
            anchorPrice = _sortedAnchorFeed[_anchorMiddle]; // Return the middle
        } else {
            // arrayPrices.length is even
            anchorPrice = (_sortedAnchorFeed[_anchorMiddle] / 2) + (_sortedAnchorFeed[_anchorMiddle - 1] / 2); // Return the average of middle pair
        }
    }

    // TWAP Price of 1 VADER in USD
    function getTWAPPrice() public view returns (uint256) {
        if (arrayPrices.length == 0) {
            return one; // Edge case for first USDV mint
        }
        return (accumulatedPrice - startIntervalAccumulatedPrice) / (block.timestamp - startIntervalTime);
    }

    // The correct amount of Vader for an input of USDV
    function getVADERAmount(uint256 USDVAmount) external view returns (uint256 vaderAmount) {
        uint256 _price = getTWAPPrice();
        return (_price * USDVAmount) / one;
    }

    // The correct amount of USDV for an input of VADER
    function getUSDVAmount(uint256 vaderAmount) external view returns (uint256 USDVAmount) {
        uint256 _price = getTWAPPrice();
        return (vaderAmount * one) / _price;
    }

    //======================================ASSETS=========================================//

    // Move funds in
    function moveTokenToPools(address _token, uint256 _amount) internal returns (uint256 safeAmount) {
        if (isBase(_token) || iPOOLS(POOLS()).isSynth(_token)) {
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
            _sendFunds(_collateralAsset, _member, _amount); // Send Base
        } else if (isPool(_collateralAsset)) {
            iPOOLS(POOLS()).unlockUnits(_amount, _collateralAsset, _member); // Unlock units to member
        }
    }

    // @dev Assumes `_token` is trusted (is a base asset or synth) and supports
    function _getFunds(address _token, uint256 _amount) internal returns (uint256) {
        uint256 _balance = iERC20(_token).balanceOf(address(this));
        require(iERC20(_token).transferFrom(msg.sender, address(this), _amount), "!Transfer"); // safeErc20 not needed; _token trusted
        return iERC20(_token).balanceOf(address(this)) - _balance;
    }

    // @dev Assumes `_token` is trusted (is a base asset or synth)
    function _sendFunds(
        address _token,
        address _member,
        uint256 _amount
    ) internal {
        require(iERC20(_token).transfer(_member, _amount), "!Transfer"); // safeErc20 not needed; _token trusted
    }

    //======================================HELPERS=========================================//

    function updateVADER(address newAddress) external {
        require(msg.sender == GovernorAlpha(), "!VADER");
        VADER = newAddress;
    }

    function isBase(address token) public view returns (bool base) {
        return token == VADER || token == USDV();
    }

    function reserveUSDV() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveUSDV(); // Balance
    }

    function reserveVADER() public view returns (uint256) {
        return iRESERVE(RESERVE()).reserveVADER(); // Balance
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

    //============================== HELPERS ================================//

    function GovernorAlpha() internal view returns (address) {
        return iVADER(VADER).GovernorAlpha();
    }

    function USDV() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).USDV();
    }

    function RESERVE() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).RESERVE();
    }

    function POOLS() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).POOLS();
    }

    function FACTORY() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).FACTORY();
    }

    function UTILS() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).UTILS();
    }

    function TIMELOCK() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).TIMELOCK();
    }
}
