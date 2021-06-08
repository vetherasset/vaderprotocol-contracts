// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

import "./Synth.sol";

// Factory Contract
contract Factory {

    address public immutable POOLS;

    address[] public arraySynths;
    mapping(address => address) private mapToken_Synth;

    event CreateSynth(address indexed token, address indexed pool);

    modifier onlyPOOLS() {
        require(msg.sender == POOLS, "!POOLS");
        _;
    }

    constructor(address _pools) {
        POOLS = _pools;
    }

    //Create a synth asset
    function deploySynth(address token) external onlyPOOLS returns (address synth) {
        require(mapToken_Synth[token] == address(0), "CreateErr");
        synth = address(new Synth(token));
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

    function getSynth(address token) external view returns (address synth){
        return mapToken_Synth[token];
    }
    function isSynth(address token) public view returns (bool _exists){
        return mapToken_Synth[token] != address(0);
    }

    function _addSynth(address _token, address _synth) internal {
        mapToken_Synth[_token] = _synth;
        arraySynths.push(_synth);
    }
}
