// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

// Interfaces
import "./interfaces/iERC20.sol";
import "./interfaces/iDAO.sol";
import "./interfaces/iVADER.sol";
import "./interfaces/iUSDV.sol";

contract Reserve {

    address public VADER;

    uint256 public lastGranted;
    uint256 public minGrantTime;

    uint256 public nextEraTime;
    uint256 public splitForUSDV;
    uint256 public allocatedVADER;

    // Only DAO can execute
    modifier onlyDAO() {
        require(msg.sender == DAO() || msg.sender == DEPLOYER(), "Not DAO");
        _;
    }
    // Only DAO can execute
    modifier onlySystem() {
        require(isPermitted(msg.sender));
        _;
    }

    function isPermitted(address _address) private view returns(bool _permitted){
        if(_address == VAULT() || _address == ROUTER()){
            _permitted = true;
        }
    }

    //=====================================CREATION=========================================//
 
    constructor() {}

    // Can only be called once
    function init(address _vader) external {
        if(VADER == address(0)){
            VADER = _vader;
            minGrantTime = 2592000;
            nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra();
            splitForUSDV = 6700;
            iERC20(VADER).approve(USDV(), type(uint).max);
        }
    }
    
    //=========================================DAO=========================================//

    function setParams(uint256 newSplit, uint256 newDelay) external onlyDAO {
        splitForUSDV = newSplit;
        minGrantTime = newDelay;
    }

    // Can issue grants
    function grant(address recipient, uint256 amount) public onlyDAO {
        require((block.timestamp - lastGranted) >= minGrantTime, "not too fast");
        lastGranted = block.timestamp;
        uint256 _reserveForGrant = reserveUSDV() / 10;
        if(amount > _reserveForGrant){
            amount = _reserveForGrant;
        }
        iERC20(USDV()).transfer(recipient, amount);
    }

    //======================================RESERVE SPlIT========================================//

    // System addresses can request an amount up to the balance
    function requestFunds(address base, address recipient, uint256 amount) external onlySystem returns(uint256) {
        checkReserve();
        uint256 _reserve;
        if(base == VADER) {
            _reserve = reserveVADER();
            if(amount > _reserve){
                amount = _reserve;
            }
        } else if(base == USDV()) {
            _reserve = reserveUSDV();
            if(amount > _reserve){
                amount = _reserve;
            }
        }
        iERC20(base).transfer(recipient, amount);
        return amount;
    }

    // System addresses can request an amount up to the balance
    function requestFundsStrict(address base, address recipient, uint256 amount) external onlySystem returns(uint256) {
        checkReserve();
        if(base == VADER) {
            require(reserveVADER() > amount, "Insufficient VADER Reserve");
        } else if(base == USDV()) {
            require(reserveUSDV() > amount, "Insufficient USDV Reserve");
        }
        iERC20(base).transfer(recipient, amount);
        return amount;
    }

    // Internal - Update Reserve function
    // Anchor (VADER): 33%
    // Asset && VAULT (USDV()): 67%
    function checkReserve() public onlySystem {
        if (block.timestamp >= nextEraTime && iVADER(VADER).emitting()) {
            // If new Era
            nextEraTime = block.timestamp + iVADER(VADER).secondsPerEra();
            uint256 _unallocatedVADER = unallocatedVADER(); // Get unallocated VADER
            if (_unallocatedVADER >= 2) {
                uint256 _USDVShare = (_unallocatedVADER * splitForUSDV) / 10000; // Get 67%
                iUSDV(USDV()).convert(_USDVShare); // Convert it to USDV()
            }
            allocatedVADER = reserveVADER(); // The remaining VADER is now allocated
        }
    }

    //=========================================HELPERS=========================================//

    function reserveVADER() public view returns (uint256) {
        return iERC20(VADER).balanceOf(address(this));
    }

    function reserveUSDV() public view returns (uint256) {
        return iERC20(USDV()).balanceOf(address(this));
    }

    function unallocatedVADER() public view returns (uint256 amount) {
        if(reserveVADER() < allocatedVADER){
            amount = reserveVADER();
        } else {
            amount = reserveVADER() - allocatedVADER;
        }
    }

    //============================== HELPERS ================================//

    function DAO() internal view returns(address){
        return iVADER(VADER).DAO();
    }
    function DEPLOYER() internal view returns(address){
        return iVADER(VADER).DEPLOYER();
    }
    function USDV() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).USDV();
    }
    function VAULT() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).VAULT();
    }
    function ROUTER() internal view returns(address){
        return iDAO(iVADER(VADER).DAO()).ROUTER();
    }

}
