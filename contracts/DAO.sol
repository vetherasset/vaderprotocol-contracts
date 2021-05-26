// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iVADER.sol";
import "./interfaces/iRESERVE.sol";
import "./interfaces/iVAULT.sol";
import "./interfaces/iROUTER.sol";

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
    uint256 public coolOffPeriod;

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

    // Only COUNCIL can execute
    modifier onlyCouncil() {
        require(msg.sender == COUNCIL, "!Council");
        _;
    }

    //=====================================CREATION=========================================//
 
    constructor() {
        COUNCIL = msg.sender; // Deployer is first Council
        coolOffPeriod = 1;
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
    // Action with parameters
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
        voteWeight = countMemberVotes(proposalID);
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
        bytes memory _type = bytes(mapPID_type[proposalID]);
        if (isEqual(_type, "GRANT")) {
            GrantDetails memory _grant = mapPID_grant[proposalID];
            iRESERVE(RESERVE).grant(_grant.recipient, _grant.amount);
        } else if (isEqual(_type, "UTILS")) {
            UTILS = mapPID_address[proposalID];
        } else if (isEqual(_type, "RESERVE")) {
            RESERVE = mapPID_address[proposalID];
        }else if (isEqual(_type, "DAO")) {
            iVADER(VADER).changeDAO(mapPID_address[proposalID]);
        } else if (isEqual(_type, "EMISSIONS")) {
            iVADER(VADER).flipEmissions();
        } else if (isEqual(_type, "MINTING")) {
            iVADER(VADER).flipMinting();
        } else if (isEqual(_type, "VADER_PARAMS")) {
            ParamDetails memory _params = mapPID_params[proposalID];
            iVADER(VADER).setParams(_params.p1, _params.p2);
        } else if (isEqual(_type, "ROUTER_PARAMS")) {
            ParamDetails memory _params = mapPID_params[proposalID];
            iROUTER(ROUTER).setParams(_params.p1, _params.p2, _params.p3, _params.p4);
        }
        completeProposal(proposalID);
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

    //============================== CONSENSUS ================================//

    function countMemberVotes(uint256 _proposalID) internal returns (uint256 voteWeight) {
        mapPID_votes[_proposalID] -= mapPIDMember_votes[_proposalID][msg.sender];
        if(msg.sender == COUNCIL){
            voteWeight = iVAULT(VAULT).totalWeight(); // Full weighting for Council EOA
            if(voteWeight == 0){
                voteWeight = 1; // Edge case if no one in vault
            }
        } else {
            voteWeight = iVAULT(VAULT).getMemberWeight(msg.sender); // Normal weighting
        }
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

    function isEqual(bytes memory part1, bytes memory part2) internal pure returns (bool) {
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

    //============================== HELPERS ================================//

    function getVotes(uint256 _proposalID) external view returns (uint256) {
        return mapPID_votes[_proposalID];
    }
    function getMemberVotes(uint256 _proposalID, address member) external view returns (uint256) {
        return mapPIDMember_votes[_proposalID][member];
    }
    function getPIDType(uint256 _proposalID) external view returns (string memory) {
        return mapPID_type[_proposalID];
    }
}
