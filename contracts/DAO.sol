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

    // uint256 public proposalCount;

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

    // mapping(uint256 => GrantDetails) public mapPID_grant;
    // mapping(uint256 => address) public mapPID_address;
    // mapping(uint256 => ParamDetails) public mapPID_params;

    // mapping(uint256 => string) public mapPID_type;
    // mapping(uint256 => uint256) public mapPID_votes;
    // mapping(uint256 => uint256) public mapPID_timeStart;
    // mapping(uint256 => bool) public mapPID_finalising;
    // mapping(uint256 => bool) public mapPID_finalised;
    // mapping(uint256 => mapping(address => uint256)) public mapPIDMember_votes;

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

    //=====================================CREATION=========================================//
 
    constructor() {
        COUNCIL = msg.sender; // Deployer is first Council
        coolOffPeriod = 1; // Set 2 days
        proposalFinalised = true;
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
        require(proposalFinalised, "Existing proposal");
        string memory typeStr = "GRANT";
        proposalType = typeStr;
        GrantDetails memory grant;
        grant.recipient = recipient;
        grant.amount = amount;
        proposedGrant = grant;
        emit NewProposal(msg.sender, typeStr);
    }

    // Action with address parameter
    function newAddressProposal(string memory typeStr, address newAddress) external {
        require(proposalFinalised, "Existing proposal");
        require(newAddress != address(0), "No address proposed");
        proposedAddress = newAddress;
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }

    // Action with no parameters
    function newActionProposal(string memory typeStr) external {
        require(proposalFinalised, "Existing proposal");
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }
    // Action with parameters
    function newParamProposal(string memory typeStr, uint256 p1, uint256 p2, uint256 p3, uint256 p4) external {
        require(proposalFinalised, "Existing proposal");
        ParamDetails memory params;
        params.p1 = p1; params.p2 = p2; params.p3 = p3; params.p4 = p4;
        proposedParams = params;
        proposalType = typeStr;
        emit NewProposal(msg.sender, typeStr);
    }

    //============================== VOTE && FINALISE ================================//

    // Vote for a proposal
    function voteForProposal() external returns (uint256 voteWeight) {
        bytes memory _type = bytes(proposalType);
        voteWeight = countMemberVotes(true);
        if (hasQuorumFor() && !proposalFinalising) {
            if (isEqual(_type, "DAO") || isEqual(_type, "UTILS") || isEqual(_type, "RESERVE")) {
                if (hasMajorityFor()) {
                    _finalise();
                }
            } else {
                _finalise();
            }
        }
        emit NewVote(msg.sender, voteWeight, votesFor, true, string(_type));
    }

    function _finalise() internal {
        proposalFinalising = true;
        proposalTimeStart = block.timestamp;
        emit ProposalFinalising(msg.sender, block.timestamp + coolOffPeriod, string(bytes(proposalType)));
    }

    // Allow minority to cancel
    function voteAgainstProposal() external returns (uint256 voteWeight)  {
        voteWeight = countMemberVotes(false);
        if (hasMinorityAgainst() && proposalFinalising) {
            _completeProposal();
        }
        emit NewVote(msg.sender, voteWeight, votesAgainst, false, string(bytes(proposalType)));
    }

    // Proposal with quorum can finalise after cool off period
    function finaliseProposal() external {
        require((block.timestamp - proposalTimeStart) > coolOffPeriod, "Must be after cool off");
        require(proposalFinalising, "Must be finalising");
        require(!proposalFinalised, "Must not be already done");
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
        } else if (isEqual(_type, "EMISSIONS")) {
            iVADER(VADER).flipEmissions();
        } else if (isEqual(_type, "MINTING")) {
            iVADER(VADER).flipMinting();
        } else if (isEqual(_type, "VADER_PARAMS")) {
            ParamDetails memory _params = proposedParams;
            iVADER(VADER).setParams(_params.p1, _params.p2);
        } else if (isEqual(_type, "ROUTER_PARAMS")) {
            ParamDetails memory _params = proposedParams;
            iROUTER(ROUTER).setParams(_params.p1, _params.p2, _params.p3, _params.p4);
        }
        _completeProposal();
    }

    function _completeProposal() internal {
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

    function countMemberVotes(bool isFor) internal returns (uint256 voteWeight) {
        if(isFor){
            votesFor -= mapMember_votesFor[msg.sender];
            if(msg.sender == COUNCIL){
                voteWeight = iVAULT(VAULT).totalWeight(); // Full weighting for Council EOA
                if(voteWeight == 0){
                    voteWeight = 1; // Edge case if no one in vault
                }
            } else {
                voteWeight = iVAULT(VAULT).getMemberWeight(msg.sender); // Normal weighting
            }
            votesFor += voteWeight;
            mapMember_votesFor[msg.sender] = voteWeight;
        } else {
            votesAgainst -= mapMember_votesAgainst[msg.sender];
            if(msg.sender == COUNCIL){
                voteWeight = iVAULT(VAULT).totalWeight(); // Full weighting for Council EOA
                if(voteWeight == 0){
                    voteWeight = 1; // Edge case if no one in vault
                }
            } else {
                voteWeight = iVAULT(VAULT).getMemberWeight(msg.sender); // Normal weighting
            }
            votesAgainst += voteWeight;
            mapMember_votesAgainst[msg.sender] = voteWeight;
        }
       
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

    function getVotes() external view returns (uint256) {
        return votesFor;
    }
    function getMemberVotes(address member) external view returns (uint256) {
        return mapMember_votesFor[member];
    }
}
