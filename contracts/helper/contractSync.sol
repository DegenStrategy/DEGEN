
// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

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
}

interface INFTstaking {
	function setAdmin() external;
}


contract DTXsyncContracts {
    address public immutable tokenDTX;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;


    constructor(address _dtx) {
        tokenDTX = _dtx;
    }

    function updateAll() external {
        updatePoolsOwner();
        updatePoolsInSideContracts();
        updateMasterchef();
		nftStaking();
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

    function updatePoolsOwner() public {
        updatePools();

        IacPool(acPool1).setAdmin();
        IacPool(acPool2).setAdmin();
        IacPool(acPool3).setAdmin();
        IacPool(acPool4).setAdmin();
        IacPool(acPool5).setAdmin();
        IacPool(acPool6).setAdmin();
    }

	function syncCreditContract() public {
        address governor = IDTX(tokenDTX).governor();
        
        IChange(IGovernor(governor).consensusContract()).syncCreditContract();
        IChange(IGovernor(governor).farmContract()).syncCreditContract();
        IChange(IGovernor(governor).fibonacceningContract()).syncCreditContract();
        IChange(IGovernor(governor).basicContract()).syncCreditContract();
    }

    //updates allocation contract owner, nft staking(admin)
    function nftStaking() public {
        address governor = IDTX(tokenDTX).governor();
		address _stakingContract = IGovernor(governor).nftStakingContract();

        IChange(IGovernor(governor).nftAllocationContract()).changeGovernor();
        INFTstaking(_stakingContract).setAdmin();
    }
	
    
    function updateMasterchef() public {
		address governor = IDTX(tokenDTX).governor();

        IChange(IGovernor(governor).farmContract()).setMasterchef();
        IChange(IGovernor(governor).fibonacceningContract()).setMasterchef();
    }
}
