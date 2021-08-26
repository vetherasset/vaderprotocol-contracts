// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "./interfaces/SafeERC20.sol";
import "./interfaces/iERC20.sol";
import "./interfaces/iGovernorAlpha.sol";
import "./interfaces/iUTILS.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iROUTER.sol";
import "./interfaces/iPOOLS.sol";
import "./interfaces/iFACTORY.sol";
import "./interfaces/iSYNTH.sol";

contract Vault {
    using SafeERC20 for ExternalERC20;

    // Parameters
    uint256 private constant secondsPerYear = 1; //31536000;

    address public VADER;

    uint256 public minimumDepositTime;
    uint256 public totalWeight;

    mapping(address => uint256) private mapAsset_deposit;
    mapping(address => uint256) private mapAsset_balance;
    mapping(address => uint256) private mapAsset_lastHarvestedTime;
    mapping(address => uint256) private mapMember_weight;

    mapping(address => mapping(address => uint256)) private mapMemberAsset_deposit;
    mapping(address => mapping(address => uint256)) private mapMemberAsset_lastTime;

    // notice A record of each accounts delegate
    mapping (address => address) public delegates;

    // @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    // @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    // @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    // @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    // @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // @notice A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    // Events
    // @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    // @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    event MemberDeposits(
        address indexed asset,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event MemberWithdraws(
        address indexed asset,
        address indexed member,
        uint256 amount,
        uint256 weight,
        uint256 totalWeight
    );
    event Harvests(
        address indexed asset,
        uint256 reward
    );

    // Only TIMELOCK can execute
    modifier onlyTIMELOCK() {
        require(msg.sender == TIMELOCK(), "!TIMELOCK");
        _;
    }

    constructor(address _vader) {
        VADER = _vader;
        minimumDepositTime = 1;
    }

    //====================================== TIMELOCK ======================================//
    // Can set params
    function setParams(
        uint256 newDepositTime
    ) external onlyTIMELOCK {
        minimumDepositTime = newDepositTime;
    }

    //======================================DEPOSITS========================================//

    // Deposit USDV or SYNTHS
    function deposit(address asset, uint256 amount) external  returns (uint256) {
        return depositForMember(asset, msg.sender, amount);
    }

    // Wrapper for contracts
    function depositForMember(
        address asset,
        address member,
        uint256 amount
    ) public returns (uint256) {
        require(((iFACTORY(FACTORY()).isSynth(asset)) || asset == USDV()), "!Permitted"); // Only Synths or USDV
        require(iERC20(asset).transferFrom(msg.sender, address(this), amount));
        return _deposit(asset, member, amount);
    }

    function _deposit(
        address _asset,
        address _member,
        uint256 _amount
    ) internal returns (uint256 weight) {
        mapMemberAsset_lastTime[_member][_asset] = block.timestamp; // Time of deposit
        mapMemberAsset_deposit[_member][_asset] += _amount; // Record deposit for member
        mapAsset_deposit[_asset] += _amount; // Record total deposit
        mapAsset_balance[_asset] = iERC20(_asset).balanceOf(address(this)); // sync deposits
        if (mapAsset_lastHarvestedTime[_asset] == 0) {
            mapAsset_lastHarvestedTime[_asset] = block.timestamp;
        }
        if (_asset == USDV()) {
            weight = _amount;
        } else {
            weight = iUTILS(UTILS()).calcSwapValueInBase(iSYNTH(_asset).TOKEN(), _amount);
        }
        mapMember_weight[_member] += weight; // Record total weight for member in USDV
        totalWeight += weight; // Total weight
        emit MemberDeposits(_asset, _member, _amount, weight, totalWeight);
        iRESERVE(RESERVE()).checkReserve();
        _moveDelegates(address(0), delegates[_member], weight);
    }

    //====================================== HARVEST ========================================//
    
    // Harvest, get reward, increase weight
    function harvest(address asset) external returns (uint256 reward) {
        reward = calcRewardForAsset(asset); 
        if (asset == USDV()) {
            iRESERVE(RESERVE()).requestFunds(USDV(), address(this), reward);
        } else {
            uint256 _actualInputBase = iRESERVE(RESERVE()).requestFunds(USDV(), POOLS(), reward);
            reward = iPOOLS(POOLS()).mintSynth(iSYNTH(asset).TOKEN(), _actualInputBase, address(this));
        }
        mapAsset_balance[asset] = iERC20(asset).balanceOf(address(this)); // sync deposits, now including the reward
        emit Harvests(asset, reward);
    }

    function calcRewardForAsset(address asset) public view returns (uint256 reward) {
        uint256 _owed = iRESERVE(RESERVE()).getVaultReward();
        uint256 _rewardsPerSecond = _owed / secondsPerYear; // Deplete over 1 year
        reward = (block.timestamp - mapAsset_lastHarvestedTime[asset]) * _rewardsPerSecond; // Multiply since last harvest
        if (reward > _owed) {
            reward = _owed; // If too much
        }
        uint256 _weight = mapAsset_deposit[asset]; // Total Deposit
        if (asset != USDV()) {
            _weight = iUTILS(UTILS()).calcValueInBase(iSYNTH(asset).TOKEN(), _weight);
        }
        reward = iUTILS(UTILS()).calcShare(_weight, totalWeight, reward); // Share of the reward
    }

    //====================================== WITHDRAW ========================================//

    // @title Withdraw `basisPoints` basis points of token `asset` from the vault to the caller.
    function withdraw(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount) {
        redeemedAmount = _processWithdraw(asset, msg.sender, basisPoints); // Get amount to withdraw
        iERC20(asset).transfer(msg.sender, redeemedAmount); // All assets are safe
    }

    // Withdraw to VADER
    function withdrawToVader(address asset, uint256 basisPoints) external returns (uint256 redeemedAmount) {
        redeemedAmount = _processWithdraw(asset, msg.sender, basisPoints); // Get amount to withdraw
        if (asset != USDV()) {
            redeemedAmount = iPOOLS(POOLS()).burnSynth(asset, address(this)); // Burn to USDV
        }
        iERC20(USDV()).approve(VADER, type(uint256).max);
        iVADER(VADER).redeemToVADERForMember(msg.sender, redeemedAmount); // Redeem to VADER for Member
    }

    function _processWithdraw(
        address _asset,
        address _member,
        uint256 _basisPoints
    ) internal returns (uint256 redeemedAmount) {
        require((block.timestamp - mapMemberAsset_lastTime[_member][_asset]) >= minimumDepositTime, "DepositTime"); // stops attacks
        redeemedAmount = iUTILS(UTILS()).calcPart(_basisPoints, calcDepositValueForMember(_asset, _member)); // Member share
        mapMemberAsset_deposit[_member][_asset] -= iUTILS(UTILS()).calcPart(_basisPoints, mapMemberAsset_deposit[_member][_asset]); // Reduce for member
        uint256 _redeemedWeight = redeemedAmount;
        if (_asset != USDV()) {
            _redeemedWeight = iUTILS(UTILS()).calcValueInBase(iSYNTH(_asset).TOKEN(), redeemedAmount);
            uint256 _memberWeight = mapMember_weight[_member];
            _redeemedWeight = iUTILS(UTILS()).calcShare(_redeemedWeight, _memberWeight, _memberWeight); // Safely reduce member weight
        }
        mapMember_weight[_member] -= _redeemedWeight; // Reduce for member
        totalWeight -= _redeemedWeight; // Reduce for total
        emit MemberWithdraws(_asset, _member, redeemedAmount, _redeemedWeight, totalWeight); // Event
        iRESERVE(RESERVE()).checkReserve();
        _moveDelegates(delegates[_member], address(0), _redeemedWeight);
    }

    // Get the value owed for a member
    function calcDepositValueForMember(address asset, address member) public view returns (uint256 value) {
        uint256 _memberDeposit = mapMemberAsset_deposit[member][asset];
        uint256 _totalDeposit = mapAsset_deposit[asset];
        uint256 _balance = mapAsset_balance[asset];
        value = iUTILS(UTILS()).calcShare(_memberDeposit, _totalDeposit, _balance); // Share of balance
    }

    //================================== GOVERNOR ALPHA =====================================//
    
    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Vader")), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "invalid signature");
        require(nonce == nonces[signatory]++, "invalid nonce");
        require(block.timestamp <= expiry, "signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = mapMember_weight[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint32 blockNumber = safe32(block.number, "block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    //============================== HELPERS ================================//

    function updateVADER(address newAddress) external {
        require(msg.sender == GovernorAlpha(), "!VADER");
        VADER = newAddress;
    }

    function reserveUSDV() external view returns (uint256) {
        return iRESERVE(RESERVE()).reserveUSDV(); // Balance
    }

    function reserveVADER() external view returns (uint256) {
        return iRESERVE(RESERVE()).reserveVADER(); // Balance
    }

    function getMemberDeposit(address member, address asset) external view returns (uint256) {
        return mapMemberAsset_deposit[member][asset];
    }

    function getMemberLastTime(address member, address asset) external view returns (uint256) {
        return mapMemberAsset_lastTime[member][asset];
    }

    function getMemberWeight(address member) external view returns (uint256) {
        return mapMember_weight[member];
    }

    function getAssetDeposit(address asset) external view returns (uint256) {
        return mapAsset_deposit[asset];
    }

    function getAssetLastTime(address asset) external view returns (uint256) {
        return mapAsset_lastHarvestedTime[asset];
    }

    function GovernorAlpha() internal view returns (address) {
        return iVADER(VADER).GovernorAlpha();
    }

    function USDV() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).USDV();
    }

    function RESERVE() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).RESERVE();
    }

    function ROUTER() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).ROUTER();
    }

    function POOLS() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).POOLS();
    }

    function FACTORY() internal view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).FACTORY();
    }

    function UTILS() public view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).UTILS();
    }

    function TIMELOCK() public view returns (address) {
        return iGovernorAlpha(GovernorAlpha()).TIMELOCK();
    }
}
