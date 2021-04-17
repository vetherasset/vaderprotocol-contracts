// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

// Interfaces
import "./iERC20.sol";
import "./iUTILS.sol";
import "./iVADER.sol";
import "./iVAULT.sol";

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
    address public VAULT;

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
    function init(address _vader, address _usdv, address _vault) public {
        require(inited == false);
        inited = true;
        VADER = _vader;
        USDV = _usdv;
        VAULT = _vault;
        iERC20(VADER).approve(VAULT, type(uint).max);
        iERC20(USDV).approve(VAULT, type(uint).max);
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
        uint _actualInputBase = moveTokenToVault(base, inputBase);
        uint _actualInputToken = moveTokenToVault(token, inputToken);
        addDepositData(msg.sender, token, _actualInputBase, _actualInputToken); 
        return iVAULT(VAULT).addLiquidity(base, token, msg.sender);
    }

    function removeLiquidity(address base, address token, uint basisPoints) public returns (uint amountBase, uint amountToken) {
        (amountBase, amountToken) = iVAULT(VAULT).removeLiquidity(base, token, basisPoints);
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
            moveTokenToVault(inputToken, inputAmount);
        } else {
            moveTokenToVault(iVAULT(VAULT).getSynth(inputToken), inputAmount);
        }
        address _base;
        if(iVAULT(VAULT).isAnchor(inputToken) || iVAULT(VAULT).isAnchor(outputToken)) {
            _base = VADER;
        } else {
            _base = USDV;
        }
        if (isBase(outputToken)) {
            // Token||Synth -> BASE
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iVAULT(VAULT).getTokenAmount(inputToken)) <= slipLimit);
            if(!inSynth){
                outputAmount = iVAULT(VAULT).swap(_base, inputToken, _member, true);
            } else {
                outputAmount = iVAULT(VAULT).burnSynth(_base, inputToken, _member);
            }
            _handlePoolReward(_base, inputToken);
        } else if (isBase(inputToken)) {
            // BASE -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iVAULT(VAULT).getBaseAmount(outputToken)) <= slipLimit);
            if(!outSynth){
                outputAmount = iVAULT(VAULT).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iVAULT(VAULT).mintSynth(_base, outputToken, _member);
            }
            _handlePoolReward(_base, outputToken);
        } else if (!isBase(inputToken) && !isBase(outputToken)) {
            // Token||Synth -> Token||Synth
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iVAULT(VAULT).getTokenAmount(inputToken)) <= slipLimit);
            if(!inSynth){
                iVAULT(VAULT).swap(_base, inputToken, VAULT, true);
            } else {
                iVAULT(VAULT).burnSynth(_base, inputToken, VAULT);
            }
            require(iUTILS(UTILS()).calcSwapSlip(inputAmount, iVAULT(VAULT).getBaseAmount(outputToken)) <= slipLimit);
            if(!outSynth){
                outputAmount = iVAULT(VAULT).swap(_base, outputToken, _member, false);
            } else {
                outputAmount = iVAULT(VAULT).mintSynth(_base, outputToken, _member);
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
            uint _baseAmount = iVAULT(VAULT).getBaseAmount(token);
            if (iVAULT(VAULT).isAsset(token)) {
                uint _share = iUTILS(UTILS()).calcShare(_baseAmount, iVAULT(VAULT).pooledUSDV(), reserveUSDV());
                rewardShare = getReducedShare(_share);
            } else if(iVAULT(VAULT).isAnchor(token)) {
                uint _share = iUTILS(UTILS()).calcShare(_baseAmount, iVAULT(VAULT).pooledVADER(), reserveVADER());
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
        iERC20(_base).transfer(VAULT, _reward);
        iVAULT(VAULT).sync(_base, _token);
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
        uint _units = iVAULT(VAULT).getMemberUnits(token, member);
        uint _B1 = iUTILS(UTILS()).calcShare(_units, iVAULT(VAULT).getUnits(token), iVAULT(VAULT).getBaseAmount(token));
        uint _T1 = iUTILS(UTILS()).calcShare(_units, iVAULT(VAULT).getUnits(token), iVAULT(VAULT).getTokenAmount(token));
        return iUTILS(UTILS()).calcCoverage(_B0, _T0, _B1, _T1);
    }

    //=====================================CURATION==========================================//

    function curatePool(address token) public {
        require(iVAULT(VAULT).isAsset(token));
        if(!isCurated(token)){
            if(curatedPoolCount < curatedPoolLimit){
                _isCurated[token] = true;
                curatedPoolCount += 1;
            }
        }
        emit Curated(msg.sender, token);
    }
    function replacePool(address oldToken, address newToken) public {
        require(iVAULT(VAULT).isAsset(newToken));
        if(iVAULT(VAULT).getBaseAmount(newToken) > iVAULT(VAULT).getBaseAmount(oldToken)){
            _isCurated[oldToken] = false;
            _isCurated[newToken] = true;
            emit Curated(msg.sender, newToken);
        }
    }

    //=====================================ANCHORS==========================================//

    function listAnchor(address token) public {
        require(arrayAnchors.length < 5);
        require(iVAULT(VAULT).isAnchor(token));
        arrayAnchors.push(token);
        arrayPrices.push(iUTILS(UTILS()).calcValueInBase(token, one));
        updateAnchorPrice(token);
    }

    function replaceAnchor(address oldToken, address newToken) public {
        require(iVAULT(VAULT).isAnchor(newToken), "Not anchor");
        require((iVAULT(VAULT).getBaseAmount(newToken) > iVAULT(VAULT).getBaseAmount(oldToken)), "Not deeper");
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
        if(iVAULT(VAULT).isAnchor(_token)){
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
    
    function borrow() public {

    }

    function payBack() public {
        
    }

    function purgeMember() public {

    }

    function getInterestPayment() public {
        
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
    function moveTokenToVault(address _token, uint _amount) internal returns(uint safeAmount) {
        if(_token == VADER || _token == USDV || iVAULT(VAULT).isSynth(_token)){
            safeAmount = _amount;
            if(tx.origin==msg.sender){
                iERC20(_token).transferTo(VAULT, _amount);
            }else{
                iERC20(_token).transferFrom(msg.sender, VAULT, _amount);
            }
        } else {
            uint _startBal = iERC20(_token).balanceOf(VAULT);
            iERC20(_token).transferFrom(msg.sender, VAULT, _amount);
            safeAmount = iERC20(_token).balanceOf(VAULT) - _startBal;
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
        } else if(iVAULT(VAULT).isAnchor(token)){
            curated = true;
        }
        return curated;
    }
}