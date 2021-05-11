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
    struct ParamDetails {
        uint256 p1;
        uint256 p2;
        uint256 p3;
        uint256 p4;
    }
     
    uint256 public proposalCount;
    uint256 public constant coolOffPeriod = 1;

    address public COUNCIL;
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
    mapping(uint256 => ParamDetails) public mapPID_params;

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

    // Only DAO can execute
    modifier onlyCouncil() {
        require(msg.sender == COUNCIL, "!Council");
        _;
    }

    //=====================================CREATION=========================================//
 
    constructor() {
        COUNCIL = msg.sender; // Deployer is first Council
    }

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
    ) external onlyCouncil {
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
    function newGrantProposal(address recipient, uint256 amount) external {
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
    function newAddressProposal(string memory typeStr, address proposedAddress) external {
        require(proposedAddress != address(0), "No address proposed");
        proposalCount += 1;
        mapPID_address[proposalCount] = proposedAddress;
        mapPID_type[proposalCount] = typeStr;
        emit NewProposal(msg.sender, proposalCount, typeStr);
    }

    // Action with no parameters
    function newActionProposal(string memory typeStr) external {
        proposalCount += 1;
        mapPID_type[proposalCount] = typeStr;
        emit NewProposal(msg.sender, proposalCount, typeStr);
    }
    // Action with no parameters
    function newParamProposal(string memory typeStr, uint256 p1, uint256 p2, uint256 p3, uint256 p4) external {
        proposalCount += 1;
        ParamDetails memory params;
        params.p1 = p1; params.p2 = p2; params.p3 = p3; params.p4 = p4;
        mapPID_params[proposalCount] = params;
        mapPID_type[proposalCount] = typeStr;
        emit NewProposal(msg.sender, proposalCount, typeStr);
    }

    //============================== VOTE && FINALISE ================================//

    // Vote for a proposal
    function voteProposal(uint256 proposalID) external returns (uint256 voteWeight) {
        bytes memory _type = bytes(mapPID_type[proposalID]);
        if(msg.sender == COUNCIL){
            voteWeight =  iVAULT(VAULT).totalWeight(); // Full weighting for Council EOA
        } else {
            voteWeight = countMemberVotes(proposalID); // Normal weighting
        }
        if (hasQuorum(proposalID) && !mapPID_finalising[proposalID]) {
            if (isEqual(_type, "DAO") || isEqual(_type, "UTILS") || isEqual(_type, "RESERVE")) {
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
    function cancelProposal(uint256 oldProposalID, uint256 newProposalID) external {
        require(mapPID_finalising[oldProposalID], "Must be finalising");
        require(hasMinority(newProposalID), "Must have minority");
        require(isEqual(bytes(mapPID_type[oldProposalID]), bytes(mapPID_type[newProposalID])), "Must be same");
        require(oldProposalID != newProposalID, "Must be different");
        mapPID_votes[oldProposalID] = 0;
        mapPID_finalising[oldProposalID]  = false;
        emit CancelProposal(
            msg.sender,
            oldProposalID,
            mapPID_votes[oldProposalID],
            mapPID_votes[newProposalID],
            iVAULT(VAULT).totalWeight()
        );
    }

    // Proposal with quorum can finalise after cool off period
    function finaliseProposal(uint256 proposalID) external {
        require((block.timestamp - mapPID_timeStart[proposalID]) > coolOffPeriod, "Must be after cool off");
        require(mapPID_finalising[proposalID], "Must be finalising");
        require(!mapPID_finalised[proposalID], "Must not be already done");
        if (!hasQuorum(proposalID)) {
            _finalise(proposalID);
        }
        bytes memory _type = bytes(mapPID_type[proposalID]);
        if (isEqual(_type, "GRANT")) {
            grantFunds(proposalID);
        } else if (isEqual(_type, "UTILS")) {
            moveUtils(proposalID);
        } else if (isEqual(_type, "RESERVE")) {
            moveReserveAddress(proposalID);
        } else if (isEqual(_type, "EMISSIONS")) {
            flipEmissions(proposalID);
        } else if (isEqual(_type, "MINTING")) {
            flipMinting(proposalID);
        } else if (isEqual(_type, "VADER_PARAMS")) {
            setVaderParams(proposalID);
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
        mapPID_finalising[_proposalID] = false;
        mapPID_finalised[_proposalID] = true;
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
        UTILS = newUTILS;
        completeProposal(_proposalID);
    }

    function moveReserveAddress(uint256 _proposalID) internal {
        address _proposedAddress = mapPID_address[_proposalID];
        require(_proposedAddress != address(0), "No address proposed");
        RESERVE = newReserve;
        completeProposal(_proposalID);
    }

    function flipEmissions(uint256 _proposalID) internal {
        iVADER(VADER).flipEmissions();
        completeProposal(_proposalID);
    }
    function flipMinting(uint256 _proposalID) internal {
        iVADER(VADER).flipMinting();
        completeProposal(_proposalID);
    }
    function setVaderParams(uint256 _proposalID) internal {
        ParamDetails memory _params = mapPID_params[_proposalID];
        iVADER(VADER).setParams(_params.p1, _params.p2);
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
        return votes > consensus;
    }

    function hasQuorum(uint256 _proposalID) public view returns (bool) {
        uint256 votes = mapPID_votes[_proposalID];
        uint256 consensus = iVAULT(VAULT).totalWeight() / 3; // >33%
        return votes > consensus;
    }

    function hasMinority(uint256 _proposalID) public view returns (bool) {
        uint256 votes = mapPID_votes[_proposalID];
        uint256 consensus = iVAULT(VAULT).totalWeight() / 6; // >16%
        return votes > consensus;
    }

    function isEqual(bytes memory part1, bytes memory part2) public pure returns (bool) {
        return sha256(part1) == sha256(part2);
    }

    //============================== COUNCIL ================================//
    // Can change COUNCIL
    function changeCouncil(address newCouncil) external onlyCouncil {
        require(newCouncil != address(0), "address err");
        COUNCIL = newCouncil;
    }

    // Can purge COUNCIL
    function purgeCouncil() external onlyCouncil {
        COUNCIL = address(0);
    }
}
