// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iVAULT.sol";
import "./interfaces/iROUTER.sol";
import "./interfaces/iERC20.sol";

import "hardhat/console.sol";

//======================================DAO=========================================//

contract DAO {
    struct GrantDetails {
        address recipient;
        uint256 amount;
    }
    struct ParamDetails {
        uint256 p1;
        uint256 p2;
        uint256 p3;
        uint256 p4;
    }

    uint256 public coolOffPeriod;
    uint256 public proposalFee;

    uint256 public proposalCount;

    address public COUNCIL;
    address public VETHER;
    address public VADER;
    address public USDV;
    address public RESERVE;
    address public VAULT;
    address public ROUTER;
    address public LENDER;
    address public POOLS;
    address public FACTORY;
    address public UTILS;

    GrantDetails public proposedGrant;
    ParamDetails public proposedParams;
    address public proposedAddress;

    string public proposalType;
    uint256 public votesFor;
    uint256 public votesAgainst;
    uint256 public proposalTimeStart;
    bool public proposalFinalising;
    bool public proposalFinalised;
    mapping(address => uint256) public mapMember_votesFor;
    mapping(address => uint256) public mapMember_votesAgainst;
    mapping(uint256 => mapping(address => bool)) public mapProposal_Member_voted;

    event NewProposal(address indexed member, string proposalType);
    event NewVote(
        address indexed member,
        uint256 voteWeight,
        uint256 totalVotes,
        bool forProposal,
        string proposalType
    );
    event ProposalFinalising(
        address indexed member,
        uint256 timeFinalised,
        string proposalType
    );
    event FinalisedProposal(
        address indexed member,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 totalWeight,
        string proposalType
    );

    // Only COUNCIL can execute
    modifier onlyCouncil() {
        require(msg.sender == COUNCIL, "!Council");
        _;
    }
    // Only VAULT can execute
    modifier onlyVault() {
        require(msg.sender == VAULT, "!Vault");
        _;
    }
    // No existing proposals
    modifier noExisting() {
        require(proposalFinalised, "Existing proposal");
        _;
    }


    //=====================================CREATION=========================================//
 
    constructor() {
        COUNCIL = msg.sender; // Deployer is first Council
        proposalFinalised = true;
        coolOffPeriod = 1; // Set 2 days
        proposalFee = 0; // 0 USDV to start
    }

    function init(
        address _vether,
        address _vader,
        address _usdv,
        address _reserve,
        address _vault,
        address _router,
        address _lender,
        address _pools,
        address _factory,
        address _utils
    ) external onlyCouncil {
        if(VADER == address(0)){
            VETHER = _vether;
            VADER = _vader;
            USDV = _usdv;
            RESERVE = _reserve;
            VAULT = _vault;
            ROUTER = _router;
            LENDER = _lender;
            POOLS = _pools;
            FACTORY = _factory;
            UTILS = _utils;
        }
    }

    // Can set params internally
    function _setParams(uint256 newPeriod, uint256 newFee) internal {
        coolOffPeriod = newPeriod;
        proposalFee = newFee;
    }

    //============================== CREATE PROPOSALS ================================//
    // Proposal with funding
    function newGrantProposal(address recipient, uint256 amount) external noExisting {
        _getProposalFee();
        string memory typeStr = "GRANT";
        proposalType = typeStr;
        GrantDetails memory grant;
        grant.recipient = recipient;
        grant.amount = amount;
        proposedGrant = grant;
        emit NewProposal(msg.sender, typeStr);
    }

    // Proposal with address parameter
    function newAddressProposal(string memory typeStr, address newAddress) external noExisting {
        _getProposalFee();
        require(newAddress != address(0), "No address proposed");
        proposedAddress = newAddress;
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }

    // Proposal with no parameters
    function newActionProposal(string memory typeStr) external noExisting {
        _getProposalFee();
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }
    // Proposal with parameters
    function newParamProposal(string memory typeStr, uint256 p1, uint256 p2, uint256 p3, uint256 p4) external noExisting {
        _getProposalFee();
        ParamDetails memory params;
        params.p1 = p1; params.p2 = p2; params.p3 = p3; params.p4 = p4;
        proposedParams = params;
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }

    function _getProposalFee() internal {
        require(iERC20(USDV).transferFrom(msg.sender, RESERVE, proposalFee));
        proposalFinalised = false;
        proposalCount += 1;
    }

    //============================== VOTE && FINALISE ================================//

    // Vote for a proposal, if meeting consensus, move to finalising
    function voteForProposal() external returns (uint256 voteWeight) {
        bytes memory _type = bytes(proposalType);
        voteWeight = _countMemberVotes(true); // This counts and adds vote weight
        if (hasQuorumFor() && !proposalFinalising) { // No voting when finalising, min consensus is Quorum
            if (isEqual(_type, "DAO") || isEqual(_type, "UTILS") || isEqual(_type, "RESERVE")) {
                if (hasMajorityFor()) {
                    _startFinalising();
                }
            } else {
                _startFinalising();
            }
        }
        emit NewVote(msg.sender, voteWeight, votesFor, true, string(_type));
    }

    // Starts the cool off period
    function _startFinalising() internal {
        proposalFinalising = true;
        proposalTimeStart = block.timestamp;
        emit ProposalFinalising(msg.sender, block.timestamp + coolOffPeriod, string(bytes(proposalType)));
    }

    // Vote against. Allow minority to cancel at any time
    function voteAgainstProposal() external returns (uint256 voteWeight)  {
        voteWeight = _countMemberVotes(false);
        if (hasMinorityAgainst()) {
            _finaliseProposal();
        }
        emit NewVote(msg.sender, voteWeight, votesAgainst, false, string(bytes(proposalType)));
    }

    // Proposal with quorum can execute after cool off period
    function executeProposal() external {
        require((block.timestamp - proposalTimeStart) > coolOffPeriod, "Must be after cool off");
        require(proposalFinalising, "Must be finalising");
        require(!proposalFinalised, "Must not be finalised");
        bytes memory _type = bytes(proposalType);
        if (isEqual(_type, "GRANT")) {
            GrantDetails memory _grant = proposedGrant;
            iRESERVE(RESERVE).grant(_grant.recipient, _grant.amount);
        } else if (isEqual(_type, "UTILS")) {
            UTILS = proposedAddress;
        } else if (isEqual(_type, "RESERVE")) {
            RESERVE = proposedAddress;
        }else if (isEqual(_type, "DAO")) {
            iVADER(VADER).changeDAO(proposedAddress);
        }else if (isEqual(_type, "COUNCIL")) {
            _changeCouncil(proposedAddress); // Allow DAO to change Council
        } else if (isEqual(_type, "EMISSIONS")) {
            iVADER(VADER).flipEmissions();
        } else if (isEqual(_type, "MINTING")) {
            iVADER(VADER).flipMinting();
        } else if (isEqual(_type, "DAO_PARAMS")) {
            ParamDetails memory _params = proposedParams;
            _setParams(_params.p1, _params.p2);
        } else if (isEqual(_type, "VADER_PARAMS")) {
            ParamDetails memory _params = proposedParams;
            iVADER(VADER).setParams(_params.p1, _params.p2);
        }else if (isEqual(_type, "ROUTER_PARAMS")) {
            ParamDetails memory _params = proposedParams;
            iROUTER(ROUTER).setParams(_params.p1, _params.p2, _params.p3, _params.p4);
        }
        _finaliseProposal();
    }

    // Emits event and resets status
    function _finaliseProposal() internal {
        string memory _typeStr = proposalType;
        emit FinalisedProposal(
            msg.sender,
            votesFor,
            votesAgainst,
            iVAULT(VAULT).totalWeight(),
            _typeStr
        );
        votesFor = 0;
        votesAgainst = 0;
        proposalFinalising = false;
        proposalFinalised = true;
    }

    //============================== CONSENSUS ================================//

    function _countMemberVotes(bool isFor) internal returns (uint256 voteWeight) {
        // If still voting, need to take away old votes for that member
        if(mapMember_votesFor[msg.sender] > 0 && mapProposal_Member_voted[proposalCount][msg.sender]){
            votesFor -= mapMember_votesFor[msg.sender];
        }
        if(mapMember_votesAgainst[msg.sender] > 0 && mapProposal_Member_voted[proposalCount][msg.sender]){
            votesAgainst -= mapMember_votesAgainst[msg.sender];
        }
        bytes memory _type = bytes(proposalType);
        if(msg.sender == COUNCIL && !isEqual(_type, "COUNCIL")){ // Don't let COUNCIL veto DAO changing it
            voteWeight = iVAULT(VAULT).totalWeight(); // Full weighting for Council EOA
            if(voteWeight == 0){
                voteWeight = 1; // Edge case if no one in vault
            }
        } else {
            voteWeight = iVAULT(VAULT).getMemberWeight(msg.sender); // Normal weighting
        }
        if(isFor){
            votesFor += voteWeight;
            mapMember_votesFor[msg.sender] = voteWeight;
        } else {
            votesAgainst += voteWeight;
            mapMember_votesAgainst[msg.sender] = voteWeight;
        }
        mapProposal_Member_voted[proposalCount][msg.sender] = true;
    }

    function hasMajorityFor() public view returns (bool) {
        uint256 consensus = iVAULT(VAULT).totalWeight() / 2; // >50%
        return votesFor > consensus;
    }

    function hasQuorumFor() public view returns (bool) {
        uint256 consensus = iVAULT(VAULT).totalWeight() / 3; // >33%
        return votesFor > consensus;
    }

    function hasMinorityAgainst() public view returns (bool) {
        uint256 consensus = iVAULT(VAULT).totalWeight() / 6; // >16%
        return votesAgainst > consensus;
    }

    // Vault can purge votes for member if they leave the vault
    function purgeVotes(address member) external onlyVault {
        votesFor -= mapMember_votesFor[member];
        votesAgainst -= mapMember_votesAgainst[member];
        mapMember_votesAgainst[member] = 0;
        mapMember_votesFor[member] = 0;
    }

    //============================== COUNCIL ================================//
    // Can change COUNCIL
    function changeCouncil(address newCouncil) external onlyCouncil {
        _changeCouncil(newCouncil);
    }
    function _changeCouncil(address _newCouncil) internal {
        require(_newCouncil != address(0), "address err");
        COUNCIL = _newCouncil;
    }

    // Can purge COUNCIL
    function purgeCouncil() external onlyCouncil {
        COUNCIL = address(0);
    }

    //============================== HELPERS ================================//

    function getMemberVotes(address member) external view returns (uint256) {
        return mapMember_votesFor[member];
    }

    function isEqual(bytes memory part1, bytes memory part2) internal pure returns (bool) {
        return sha256(part1) == sha256(part2);
    }
}
