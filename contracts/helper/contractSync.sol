
// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IMasterChef.sol";
import "../interface/INFTMining.sol";

interface IChange {
    function changeGovernor() external;
    function updatePools() external;
    function setAdmin() external;
    function setMasterchef() external;
	function syncCreditContract() external;
    function updateTreasury() external;
	function syncOwner() external;
	function updateFees() external;
    function viewVaults() external view returns(address[] memory);
}

contract DTXsyncContracts {
    address public immutable tokenDTX;
    address public immutable proxyVoting;
    address public immutable HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address public immutable PLSX;
    address public immutable INC;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;


    constructor(address _dtx, address _proxyVoting, address _plsx, address _inc) {
        tokenDTX = _dtx;
        proxyVoting = _proxyVoting;
        PLSX = _plsx;
        INC = _inc;
    }


    function updateAllInitialize() external payable {
		updatePools();
		updatePoolsDistributionContract();
        updatePoolsOwner();
        syncOwners();
        updateMasterchef();
		nftStaking();
        IChange(proxyVoting).updatePools();
        setBalanceAbove0();
		updateTreasury();
		syncCreditContract();
        updateFees();
    }

    function updateAll() external {
		updatePools();
		updatePoolsDistributionContract();
        updatePoolsOwner();
        syncOwners();
        updateMasterchef();
		nftStaking();
        IChange(proxyVoting).updatePools();
		updateTreasury();
		syncCreditContract();
        updateFees();
    }

    function updatePools() public {
        address governor = IDTX(tokenDTX).governor();

        acPool1 = IGovernor(governor).acPool1();
        acPool2 = IGovernor(governor).acPool2();
        acPool3 = IGovernor(governor).acPool3();
        acPool4 = IGovernor(governor).acPool4();
        acPool5 = IGovernor(governor).acPool5();
        acPool6 = IGovernor(governor).acPool6();
    }

	// sets admin and treasury synchronously
    function updatePoolsOwner() public {
        updatePools();

        IacPool(acPool1).setAdmin();
        IacPool(acPool2).setAdmin();
        IacPool(acPool3).setAdmin();
        IacPool(acPool4).setAdmin();
        IacPool(acPool5).setAdmin();
        IacPool(acPool6).setAdmin();
    }

    function updateTreasury() public {
        address governor = IDTX(tokenDTX).governor();
        IChange(IGovernor(governor).plsVault()).updateTreasury();
        IChange(IGovernor(governor).plsxVault()).updateTreasury();
        IChange(IGovernor(governor).incVault()).updateTreasury();
        IChange(IGovernor(governor).hexVault()).updateTreasury();
        IChange(IGovernor(governor).tshareVault()).updateTreasury();
    }

	function updatePoolsDistributionContract() public {
		address governor = IDTX(tokenDTX).governor();

		IChange(IGovernor(governor).tokenDistributionContract()).updatePools();
		IChange(IGovernor(governor).tokenDistributionContractExtraPenalty()).updatePools();
	}

	function syncCreditContract() public {
        address governor = IDTX(tokenDTX).governor();
        
        IChange(IGovernor(governor).consensusContract()).syncCreditContract();
        IChange(IGovernor(governor).farmContract()).syncCreditContract();
        IChange(IGovernor(governor).fibonacceningContract()).syncCreditContract();
        IChange(IGovernor(governor).basicContract()).syncCreditContract();
	IChange(IGovernor(governor).nftAllocationContract()).syncCreditContract();
    }

    // Sets initial balance on vaults to prevent division by zero
    // must manually transfer 1 plsx, inc and hex to the contract
    function setBalanceAbove0() public payable {
        address governor = IDTX(tokenDTX).governor();
        payable(IGovernor(governor).plsVault()).transfer(1e18); // send 1 PLS
        require(IERC20(PLSX).transfer(IGovernor(governor).plsxVault(), 1e18), "PLSX initial transfer unsuccesful!");
        require(IERC20(INC).transfer(IGovernor(governor).incVault(), 1e18), "INC initial transfer unsuccesful!");
        require(IERC20(HEX).transfer(IGovernor(governor).hexVault(), 1e8), "HEX initial transfer unsuccesful!");
    }

	function syncOwners() public {
		IGovernor governor = IGovernor(IDTX(tokenDTX).governor());
		IChange(governor.basicContract()).syncOwner();
		IChange(governor.farmContract()).syncOwner();
		IChange(governor.rewardContract()).syncOwner();
		IChange(governor.fibonacceningContract()).syncOwner();
		IChange(governor.senateContract()).syncOwner();
		IChange(governor.creditContract()).syncOwner();
		IChange(governor.nftAllocationContract()).syncOwner();
		IChange(governor.consensusContract()).syncOwner();
	}

    //updates allocation contract owner, nft staking(admin)
    function nftStaking() public {
        address governor = IDTX(tokenDTX).governor();
		address _stakingContract = IGovernor(governor).nftStakingContract();

        IChange(IGovernor(governor).nftAllocationContract()).syncOwner();
        INFTMining(_stakingContract).setAdmin();
    }

	// Update Fees for vaults
	function updateFees() public {
        address governor = IDTX(tokenDTX).governor();
        address referralContract = IGovernor(governor).rewardContract();
        address[] memory vaults = IChange(referralContract).viewVaults();
		for(uint256 i=0; i < vaults.length; i++) {
			IChange(vaults[i]).updateFees();
		}
	}
	
    
    function updateMasterchef() public {
		address governor = IDTX(tokenDTX).governor();

        IChange(IGovernor(governor).farmContract()).setMasterchef();
        IChange(IGovernor(governor).fibonacceningContract()).setMasterchef();
    }
}
