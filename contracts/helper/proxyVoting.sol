// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";

interface IHarvestContract {
    function selfHarvest(address _userAddress, uint256[] calldata _stakeID) external;
}

contract DTXvotingProxy {
    address public immutable dtxToken = ;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;



    function updatePools() external {
        address governor = IDTX(dtxToken).governor();

        acPool1 = IGovernor(governor).acPool1();
        acPool2 = IGovernor(governor).acPool2();
        acPool3 = IGovernor(governor).acPool3();
        acPool4 = IGovernor(governor).acPool4();
    }

    function proxyVote(uint256 _forID) external {
        IacPool(acPool1).voteForProposal(_forID, true);
        IacPool(acPool2).voteForProposal(_forID, true);
        IacPool(acPool3).voteForProposal(_forID, true);
        IacPool(acPool4).voteForProposal(_forID, true);
    }

    function proxySetDelegate(address _forWallet) external {
        IacPool(acPool1).setDelegate(_forWallet, true);
        IacPool(acPool2).setDelegate(_forWallet, true);
        IacPool(acPool3).setDelegate(_forWallet, true);
        IacPool(acPool4).setDelegate(_forWallet, true);
    }

    function multiSelfHarvest(
        address[] calldata _contractAddresses,
        address _userAddress,
        uint256[][] calldata _stakeIDs
    ) external {
        require(
            _contractAddresses.length == _stakeIDs.length,
            "Mismatched contracts and stake IDs length"
        );
        require(_contractAddresses.length > 0, "No contracts provided");

        for (uint256 i = 0; i < _contractAddresses.length; i++) {
            IHarvestContract(_contractAddresses[i]).selfHarvest(_userAddress, _stakeIDs[i]);
        }
    }
}
