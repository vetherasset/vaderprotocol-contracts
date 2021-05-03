// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iRESERVE.sol";
import "./interfaces/iVAULT.sol";

//======================================VADER=========================================//
contract DAO {
    struct GrantDetails {
        address recipient;
        uint256 amount;
    }

     
    uint256 public proposalCount;
    uint256 public constant coolOffPeriod = 1;

    address public VETHER;
    address public VADER;
    address public USDV;
    address public RESERVE;
    address public VAULT;
    address public ROUTER;
    address public POOLS;
    address public FACTORY;
    address public UTILS;

    mapping(uint256 => GrantDetails) public mapPID_grant;
    mapping(uint256 => address) public mapPID_address;

    mapping(uint256 => string) public mapPID_type;
    mapping(uint256 => uint256) public mapPID_votes;
    mapping(uint256 => uint256) public mapPID_timeStart;
    mapping(uint256 => bool) public mapPID_finalising;
    mapping(uint256 => bool) public mapPID_finalised;
    mapping(uint256 => mapping(address => uint256)) public mapPIDMember_votes;

    event NewProposal(address indexed member, uint256 indexed proposalID, string proposalType);
    event NewVote(
        address indexed member,
        uint256 indexed proposalID,
        uint256 voteWeight,
        uint256 totalVotes,
        string proposalType
    );
    event ProposalFinalising(
        address indexed member,
        uint256 indexed proposalID,
        uint256 timeFinalised,
        string proposalType
    );
    event CancelProposal(
        address indexed member,
        uint256 indexed oldProposalID,
        uint256 oldVotes,
        uint256 newVotes,
        uint256 totalWeight
    );
    event FinalisedProposal(
        address indexed member,
        uint256 indexed proposalID,
        uint256 votesCast,
        uint256 totalWeight,
        string proposalType
    );

    //=====================================CREATION=========================================//
 
    constructor() {}

    function init(
        address _vether,
        address _vader,
        address _usdv,
        address _reserve,
        address _vault,
        address _router,
        address _pools,
        address _factory,
        address _utils
    ) public {
        if(VADER == address(0)){
            VETHER = _vether;
            VADER = _vader;
            USDV = _usdv;
            RESERVE = _reserve;
            VAULT = _vault;
            ROUTER = _router;
            POOLS = _pools;
            FACTORY = _factory;
            UTILS = _utils;
        }
    }

    //============================== CREATE PROPOSALS ================================//
    // Action with funding
    function newGrantProposal(address recipient, uint256 amount) public {
        string memory typeStr = "GRANT";
        proposalCount += 1;
        mapPID_type[proposalCount] = typeStr;
        GrantDetails memory grant;
        grant.recipient = recipient;
        grant.amount = amount;
        mapPID_grant[proposalCount] = grant;
        emit NewProposal(msg.sender, proposalCount, typeStr);
    }

    // Action with address parameter
    function newAddressProposal(address proposedAddress, string memory typeStr) public {
        proposalCount += 1;
        mapPID_address[proposalCount] = proposedAddress;
        mapPID_type[proposalCount] = typeStr;
        emit NewProposal(msg.sender, proposalCount, typeStr);
    }

    //============================== VOTE && FINALISE ================================//

    // Vote for a proposal
    function voteProposal(uint256 proposalID) public returns (uint256 voteWeight) {
        bytes memory _type = bytes(mapPID_type[proposalID]);
        voteWeight = countMemberVotes(proposalID);
        if (hasQuorum(proposalID) && mapPID_finalising[proposalID] == false) {
            if (isEqual(_type, "DAO") || isEqual(_type, "UTILS") || isEqual(_type, "REWARD")) {
                if (hasMajority(proposalID)) {
                    _finalise(proposalID);
                }
            } else {
                _finalise(proposalID);
            }
        }
        emit NewVote(msg.sender, proposalID, voteWeight, mapPID_votes[proposalID], string(_type));
    }

    function _finalise(uint256 _proposalID) internal {
        bytes memory _type = bytes(mapPID_type[_proposalID]);
        mapPID_finalising[_proposalID] = true;
        mapPID_timeStart[_proposalID] = block.timestamp;
        emit ProposalFinalising(msg.sender, _proposalID, block.timestamp + coolOffPeriod, string(_type));
    }

    // If an existing proposal, allow a minority to cancel
    function cancelProposal(uint256 oldProposalID, uint256 newProposalID) public {
        require(mapPID_finalising[oldProposalID], "Must be finalising");
        require(hasMinority(newProposalID), "Must have minority");
        require(isEqual(bytes(mapPID_type[oldProposalID]), bytes(mapPID_type[newProposalID])), "Must be same");
        mapPID_votes[oldProposalID] = 0;
        emit CancelProposal(
            msg.sender,
            oldProposalID,
            mapPID_votes[oldProposalID],
            mapPID_votes[newProposalID],
            iVAULT(VAULT).totalWeight()
        );
    }

    // Proposal with quorum can finalise after cool off period
    function finaliseProposal(uint256 proposalID) public {
        require((block.timestamp - mapPID_timeStart[proposalID]) > coolOffPeriod, "Must be after cool off");
        require(mapPID_finalising[proposalID] == true, "Must be finalising");
        if (!hasQuorum(proposalID)) {
            _finalise(proposalID);
        }
        bytes memory _type = bytes(mapPID_type[proposalID]);
        if (isEqual(_type, "GRANT")) {
            grantFunds(proposalID);
        } else if (isEqual(_type, "UTILS")) {
            moveUtils(proposalID);
        } else if (isEqual(_type, "REWARD")) {
            moveRewardAddress(proposalID);
        }
    }

    function completeProposal(uint256 _proposalID) internal {
        string memory _typeStr = mapPID_type[_proposalID];
        emit FinalisedProposal(
            msg.sender,
            _proposalID,
            mapPID_votes[_proposalID],
            iVAULT(VAULT).totalWeight(),
            _typeStr
        );
        mapPID_votes[_proposalID] = 0;
        mapPID_finalised[_proposalID] = true;
        mapPID_finalising[_proposalID] = false;
    }

    //============================== BUSINESS LOGIC ================================//

    function grantFunds(uint256 _proposalID) internal {
        GrantDetails memory _grant = mapPID_grant[_proposalID];
        completeProposal(_proposalID);
        iRESERVE(RESERVE).grant(_grant.recipient, _grant.amount);
    }

    function moveUtils(uint256 _proposalID) internal {
        address _proposedAddress = mapPID_address[_proposalID];
        require(_proposedAddress != address(0), "No address proposed");
        changeUTILS(_proposedAddress);
        completeProposal(_proposalID);
    }

    function moveRewardAddress(uint256 _proposalID) internal {
        address _proposedAddress = mapPID_address[_proposalID];
        require(_proposedAddress != address(0), "No address proposed");
        setReserve(_proposedAddress);
        completeProposal(_proposalID);
    }

    //============================== CONSENSUS ================================//

    function countMemberVotes(uint256 _proposalID) internal returns (uint256 voteWeight) {
        mapPID_votes[_proposalID] -= mapPIDMember_votes[_proposalID][msg.sender];
        voteWeight = iVAULT(VAULT).getMemberWeight(msg.sender);
        mapPID_votes[_proposalID] += voteWeight;
        mapPIDMember_votes[_proposalID][msg.sender] = voteWeight;
    }

    function hasMajority(uint256 _proposalID) public view returns (bool) {
        uint256 votes = mapPID_votes[_proposalID];
        uint256 consensus = iVAULT(VAULT).totalWeight() / 2; // >50%
        if (votes > consensus) {
            return true;
        } else {
            return false;
        }
    }

    function hasQuorum(uint256 _proposalID) public view returns (bool) {
        uint256 votes = mapPID_votes[_proposalID];
        uint256 consensus = iVAULT(VAULT).totalWeight() / 3; // >33%
        if (votes > consensus) {
            return true;
        } else {
            return false;
        }
    }

    function hasMinority(uint256 _proposalID) public view returns (bool) {
        uint256 votes = mapPID_votes[_proposalID];
        uint256 consensus = iVAULT(VAULT).totalWeight() / 6; // >16%
        if (votes > consensus) {
            return true;
        } else {
            return false;
        }
    }

    function isEqual(bytes memory part1, bytes memory part2) public pure returns (bool) {
        if (sha256(part1) == sha256(part2)) {
            return true;
        } else {
            return false;
        }
    }

    //============================== CONSENSUS ================================//
        // Can set reward address
    function setReserve(address newReserve) internal {
        require(newReserve != address(0), "address err");
        RESERVE = newReserve;
    }

    // Can change UTILS
    function changeUTILS(address newUTILS) internal {
        require(newUTILS != address(0), "address err");
        UTILS = newUTILS;
    }
}
