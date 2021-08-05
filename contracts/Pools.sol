// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/SafeERC20.sol";
import "./interfaces/iERC20.sol";
import "./interfaces/iGovernorAlpha.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iROUTER.sol";
import "./interfaces/iFACTORY.sol";

contract Pools {
    using SafeERC20 for ExternalERC20;

    // Parameters
    uint256 public pooledVADER;
    uint256 public pooledUSDV;

    address public immutable VADER;

    mapping(address => bool) internal _isAsset;
    mapping(address => bool) internal _isAnchor;

    mapping(address => uint256) public mapToken_Units;
    mapping(address => mapping(address => uint256)) public mapTokenMember_Units;
    mapping(address => uint256) public mapToken_baseAmount;
    mapping(address => uint256) public mapToken_tokenAmount;

    // Events
    event AddLiquidity(
        address indexed member,
        address indexed base,
        uint256 baseAmount,
        address indexed token,
        uint256 tokenAmount,
        uint256 liquidityUnits
    );
    event RemoveLiquidity(
        address indexed member,
        address indexed base,
        uint256 baseAmount,
        address indexed token,
        uint256 tokenAmount,
        uint256 liquidityUnits,
        uint256 totalUnits
    );
    event Swap(
        address indexed member,
        address indexed inputToken,
        uint256 inputAmount,
        address indexed outputToken,
        uint256 outputAmount,
        uint256 swapFee
    );
    event Sync(address indexed token, address indexed pool, uint256 addedAmount);
    event MintSynth(
        address indexed member,
        address indexed base,
        uint256 baseAmount,
        address indexed token,
        uint256 synthAmount
    );
    event BurnSynth(
        address indexed member,
        address indexed base,
        uint256 baseAmount,
        address indexed token,
        uint256 synthAmount
    );
    event SynthSync(address indexed token, uint256 burntSynth, uint256 deletedUnits);

    // Only SYSTEM can execute
    modifier onlySystem() {
        require((msg.sender == ROUTER() || msg.sender == VAULT() || msg.sender == LENDER()), "!SYSTEM");
        _;
    }

    //=====================================CREATION=========================================//

    constructor(address _vader) {
        VADER = _vader;
    }

    //====================================LIQUIDITY=========================================//

    function addLiquidity(
        address base,
        uint256 inputBase,
        address token,
        uint256 inputToken,
        address member
    ) external onlySystem returns (uint256 liquidityUnits) {
        require(isBase(base), "!Base");
        require(!isBase(token), "USDV || VADER"); // Prohibited
        // uint256 _actualInputBase;
        if (base == VADER) {
            require(getSynth(token) == address(0), "Synth!");
            if (!_isAnchor[token]) {
                // If new Anchor
                _isAnchor[token] = true;
            }
            pooledVADER += inputBase;
        } else {
            if (!_isAsset[token]) {
                // If new Asset
                _isAsset[token] = true;
            }
            pooledUSDV += inputBase;
        }

        liquidityUnits = iUTILS(UTILS()).calcLiquidityUnits(
            inputBase,
            mapToken_baseAmount[token],
            inputToken,
            mapToken_tokenAmount[token],
            mapToken_Units[token]
        );
        mapTokenMember_Units[token][member] += liquidityUnits; // Add units to member
        mapToken_Units[token] += liquidityUnits; // Add in total
        mapToken_baseAmount[token] += inputBase; // Add BASE
        mapToken_tokenAmount[token] += inputToken; // Add token
        emit AddLiquidity(member, base, inputBase, token, inputToken, liquidityUnits);
    }

    function removeLiquidity(
        address base,
        address token,
        uint256 basisPoints,
        address member
    ) external onlySystem returns (uint256 units, uint256 outputBase, uint256 outputToken) {
        require(isBase(base), "!Base");
        (units, outputBase, outputToken) = iUTILS(UTILS()).getMemberShare(basisPoints, token, member);
        mapToken_Units[token] -= units;
        mapTokenMember_Units[token][member] -= units;
        mapToken_baseAmount[token] -= outputBase;
        mapToken_tokenAmount[token] -= outputToken;
        emit RemoveLiquidity(member, base, outputBase, token, outputToken, units, mapToken_Units[token]);
        transferOut(base, outputBase, member);
        transferOut(token, outputToken, member);
    }

    //=======================================SWAP===========================================//

    // Called only by a router
    function swap(
        address base,
        address token,
        uint256 amount,
        address member,
        bool toBase
    ) external onlySystem returns (uint256 outputAmount) {
        require(isBase(base), "!Base");
        if (toBase) {
            outputAmount = iUTILS(UTILS()).calcSwapOutput(
                amount,
                mapToken_tokenAmount[token],
                mapToken_baseAmount[token]
            );
            uint256 _swapFee =
                iUTILS(UTILS()).calcSwapFee(amount, mapToken_tokenAmount[token], mapToken_baseAmount[token]);
            mapToken_tokenAmount[token] += amount;
            mapToken_baseAmount[token] -= outputAmount;
            emit Swap(member, token, amount, base, outputAmount, _swapFee);
            transferOut(base, outputAmount, member);
        } else {
            outputAmount = iUTILS(UTILS()).calcSwapOutput(
                amount,
                mapToken_baseAmount[token],
                mapToken_tokenAmount[token]
            );
            uint256 _swapFee =
                iUTILS(UTILS()).calcSwapFee(amount, mapToken_baseAmount[token], mapToken_tokenAmount[token]);
            mapToken_baseAmount[token] += amount;
            mapToken_tokenAmount[token] -= outputAmount;
            emit Swap(member, base, amount, token, outputAmount, _swapFee);
            transferOut(token, outputAmount, member);
        }
    }

    // Add to balances directly (must send first)
    function sync(address token, uint256 inputToken, address pool) external {
        if (token == VADER) {
            pooledVADER += inputToken;
        } else if (token == USDV()) {
            pooledUSDV += inputToken;
        }
        if (isBase(token)) {
            mapToken_baseAmount[pool] += inputToken;
        } else {
            mapToken_tokenAmount[pool] += inputToken;
        }
        emit Sync(token, pool, inputToken);
    }

    //======================================SYNTH=========================================//

    // Should be done with intention, is gas-intensive
    function deploySynth(address token) external {
        require(!isBase(token) && !isAnchor(token), "VADER || USDV || ANCHOR");
        iFACTORY(FACTORY()).deploySynth(token);
    }

    // Mint a Synth against its own pool
    function mintSynth(address token, uint256 inputBase, address member) external onlySystem returns (uint256 outputAmount) {
        address synth = getSynth(token);
        require(synth != address(0), "!Synth");
        pooledUSDV += inputBase;
        outputAmount = iUTILS(UTILS()).calcSwapOutput(
            inputBase,
            mapToken_baseAmount[token],
            mapToken_tokenAmount[token]
        ); // Get output
        mapToken_baseAmount[token] += inputBase; // Add BASE
        emit MintSynth(member, USDV(), inputBase, token, outputAmount); // Mint Synth Event
        iFACTORY(FACTORY()).mintSynth(synth, member, outputAmount); // Ask factory to mint to member
    }

    // Burn a Synth to get out BASE
    function burnSynth (address token, address member) external onlySystem returns (uint256 outputBase) {
        address synth = getSynth(token);
        uint256 _actualInputSynth = iERC20(synth).balanceOf(address(this)); // Get input
        iERC20(synth).burn(_actualInputSynth); // Burn it
        outputBase = iUTILS(UTILS()).calcSwapOutput(
            _actualInputSynth,
            mapToken_tokenAmount[token],
            mapToken_baseAmount[token]
        ); // Get output
        mapToken_baseAmount[token] -= outputBase; // Remove BASE
        emit BurnSynth(member, USDV(), outputBase, token, _actualInputSynth); // Burn Synth Event
        transferOut(USDV(), outputBase, member); // Send USDV to member
    }

    // Remove a synth, make other LPs richer
    function syncSynth(address token) external {
        address synth = getSynth(token);
        uint256 _actualInputSynth = iERC20(synth).balanceOf(address(this)); // Get input
        uint256 _unitsToDelete =
            iUTILS(UTILS()).calcShare(
                _actualInputSynth,
                iERC20(synth).totalSupply(),
                mapTokenMember_Units[token][address(this)]
            ); // Pro rata
        iERC20(synth).burn(_actualInputSynth); // Burn it
        mapTokenMember_Units[token][address(this)] -= _unitsToDelete; // Delete units for self
        mapToken_Units[token] -= _unitsToDelete; // Delete units
        emit SynthSync(token, _actualInputSynth, _unitsToDelete);
    }

    //======================================LENDING=========================================//

    // // Assign units to Router
    // function lockUnits(
    //     uint256 units,
    //     address token,
    //     address member
    // ) external onlySystem {
    //     mapTokenMember_Units[token][member] -= units;
    //     mapTokenMember_Units[token][msg.sender] += units; // Assign to Router
    // }

    // // Remove units from Router
    // function unlockUnits(
    //     uint256 units,
    //     address token,
    //     address member
    // ) external onlySystem {
    //     mapTokenMember_Units[token][msg.sender] -= units;
    //     mapTokenMember_Units[token][member] += units;
    // }

    //======================================HELPERS=========================================//

    function transferOut(
        address _token,
        uint256 _amount,
        address _recipient
    ) internal {
        if (_token == VADER) {
            pooledVADER = pooledVADER - _amount; // Accounting
        } else if (_token == USDV()) {
            pooledUSDV = pooledUSDV - _amount; // Accounting
        }
        if (_recipient != address(this)) {
            ExternalERC20(_token).safeTransfer(_recipient, _amount);
        }
    }

    function isBase(address token) public view returns (bool base) {
        return token == VADER || token == USDV();
    }

    function isAsset(address token) public view returns (bool) {
        return _isAsset[token];
    }

    function isAnchor(address token) public view returns (bool) {
        return _isAnchor[token];
    }

    function getPoolAmounts(address token) external view returns (uint256, uint256) {
        return (getBaseAmount(token), getTokenAmount(token));
    }

    function getBaseAmount(address token) public view returns (uint256) {
        return mapToken_baseAmount[token];
    }

    function getTokenAmount(address token) public view returns (uint256) {
        return mapToken_tokenAmount[token];
    }

    function getUnits(address token) external view returns (uint256) {
        return mapToken_Units[token];
    }

    function getMemberUnits(address token, address member) external view returns (uint256) {
        return mapTokenMember_Units[token][member];
    }

    function getSynth(address token) public view returns (address) {
        return iFACTORY(FACTORY()).getSynth(token);
    }

    function isSynth(address token) external view returns (bool) {
        return iFACTORY(FACTORY()).isSynth(token);
    }

    function GovernorAlpha() internal view returns (address) {
        return iVADER(VADER).GovernorAlpha();
    }

    function USDV() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).USDV();
    }

    function ROUTER() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).ROUTER();
    }

    function VAULT() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).VAULT();
    }

    function LENDER() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).LENDER();
    }

    function FACTORY() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).FACTORY();
    }

    function UTILS() public view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).UTILS();
    }

}
