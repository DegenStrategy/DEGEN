
// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IMasterChef.sol";

interface IChange {
    function changeGovernor() external;
    function updatePools() external;
    function setAdmin() external;
    function setMasterchef() external;
	function syncCreditContract() external;
    function updateAddresses() external;
	function syncOwner() external;
	function updateFees() external;
    function viewVaults() external view returns(address[] memory);
    function useRewards() external;
}

contract DTXsyncContracts {
    address public immutable tokenDTX = ;
    address public immutable proxyVoting = ;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;


    function updateAllInitialize() external payable {
		updatePools();
        updatePoolsOwner();
        syncOwners();
        updateMasterchef();
        IChange(proxyVoting).updatePools();
		syncCreditContract();
        updateFees();
        updatePoolsAll();
    }

    function updateAll() external {
		updatePools();
        updatePoolsOwner();
        syncOwners();
        updateMasterchef();
        IChange(proxyVoting).updatePools();
		syncCreditContract();
        updateFees();
        updatePoolsAll();
    }

    function updatePools() public {
        address governor = IDTX(tokenDTX).governor();

        acPool1 = IGovernor(governor).acPool1();
        acPool2 = IGovernor(governor).acPool2();
        acPool3 = IGovernor(governor).acPool3();
        acPool4 = IGovernor(governor).acPool4();
    }

	// sets admin and treasury synchronously
    function updatePoolsOwner() public {
        updatePools();

        IacPool(acPool1).setAdmin();
        IacPool(acPool2).setAdmin();
        IacPool(acPool3).setAdmin();
        IacPool(acPool4).setAdmin();
    }

    function updatePoolsAll() public {
        IMasterChef _masterchef = IMasterChef(IDTX(tokenDTX).owner());
        for(uint i=0; i < _masterchef.poolLength() ; i++) {
            (, , address _pool) = _masterchef.poolInfo(i);
            if(i<4) {
                IChange(_pool).setAdmin();
            } else {
                IChange(_pool).updateAddresses();
            }
        }
    }

    function harvestVaults() public {
        IMasterChef _masterchef = IMasterChef(IDTX(tokenDTX).owner());
        for(uint i=4; i < _masterchef.poolLength() ; i++) {
            (, , address _pool) = _masterchef.poolInfo(i);
            try IChange(_pool).useRewards() {}
            catch{}
        }
    }


	function syncCreditContract() public {
        address governor = IDTX(tokenDTX).governor();
        
        IChange(IGovernor(governor).consensusContract()).syncCreditContract();
        IChange(IGovernor(governor).farmContract()).syncCreditContract();
        IChange(IGovernor(governor).basicContract()).syncCreditContract();
    }


	function syncOwners() public {
		IGovernor governor = IGovernor(IDTX(tokenDTX).governor());
		IChange(governor.basicContract()).syncOwner();
		IChange(governor.farmContract()).syncOwner();
		IChange(governor.rewardContract()).syncOwner();
		IChange(governor.creditContract()).syncOwner();
		IChange(governor.consensusContract()).syncOwner();
	}



	// Update Fees for vaults
	function updateFees() public {
        address governor = IDTX(tokenDTX).governor();
        address referralContract = IGovernor(governor).rewardContract();
        address[] memory vaults = IChange(referralContract).viewVaults();
		for(uint256 i=0; i < vaults.length; i++) {
			try IChange(vaults[i]).updateFees() {}
            catch{}
		}
	}
	
    
    function updateMasterchef() public {
		address governor = IDTX(tokenDTX).governor();

        IChange(IGovernor(governor).farmContract()).setMasterchef();
    }
}
