// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

import "./Synth.sol";

// Factory Contract
contract Factory {

    address public POOLS;

    address[] public arraySynths;
    mapping(address => address) private mapToken_Synth;
    mapping(address => bool) private _isSynth;

    event CreateSynth(address indexed token, address indexed pool);

    modifier onlyPOOLS() {
        require(msg.sender == POOLS, "!POOLS");
        _;
    }

    constructor() {}

    function init(address _pools) public {
        if(POOLS == address(0)){
            POOLS = _pools;
        }
    }

    //Create a synth asset
    function deploySynth(address token) external onlyPOOLS returns (address synth) {
        require(mapToken_Synth[token] == address(0), "CreateErr");
        Synth newSynth;
        newSynth = new Synth(token);
        synth = address(newSynth);
        _addSynth(token, synth);
        emit CreateSynth(token, synth);
    }

    function mintSynth(
        address synth,
        address member,
        uint256 amount
    ) external onlyPOOLS returns (bool) {
        Synth(synth).mint(member, amount);
        return true;
    }

    function getSynth(address token) public view returns (address synth){
        return mapToken_Synth[token];
    }
    function isSynth(address token) public view returns (bool _exists){
        bool _synthExists = _isSynth[token];
        if(_synthExists){
            return true;
        }
    }

    function _addSynth(address _token, address _synth) internal {
        mapToken_Synth[_token] = _synth;
        arraySynths.push(_synth);
        _isSynth[_synth] = true;
    }
}
