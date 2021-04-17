// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;

import "./Synth.sol"; 

// Factory Contract
contract Factory {

    bool private inited;
    address public VADER;
    address public USDV;
    address public VAULT;

    address[] public arraySynths;
    mapping(address => address) private mapToken_Synth;
    mapping(address => bool) public isSynth;
    event CreateSynth(address indexed token, address indexed pool);

    modifier onlyVAULT() {
        require(msg.sender == VAULT, "!VAULT");
        _;
    }
    
    // Minting event
    constructor(){
    }
    function init(address _vader, address _usdv, address _vault) public {
        require(inited == false);
        VADER = _vader;
        USDV = _usdv;
        VAULT = _vault;
    }

    //Create a synth asset
    function deploySynth(address token) public returns(address synth){
        require(getSynth(token) == address(0), "CreateErr");
        require(token != VADER || token != USDV);
        Synth newSynth;
        newSynth = new Synth(token);  
        synth = address(newSynth);
        _addSynth(token, synth);
        emit CreateSynth(token, synth);
        return synth;
    }

    function mintSynth(address synth, address member, uint amount) public onlyVAULT returns(bool){
         Synth(synth).mint(member, amount); 
        return true;
    }

    function getSynth(address token) public view returns (address synth){
        return mapToken_Synth[token];
    }
    function _addSynth(address _token, address _synth) internal {
        mapToken_Synth[_token] = _synth;
        arraySynths.push(_synth); 
        isSynth[_synth] = true;
    }

}