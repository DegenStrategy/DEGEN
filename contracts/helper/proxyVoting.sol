// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";

contract DTXvotingProxy {
    address public immutable dtxToken;
    
    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;


    constructor(address _dtx) {
        dtxToken = _dtx;
    }


    function updatePools() external {
        address governor = IDTX(dtxToken).governor();

        acPool1 = IGovernor(governor).acPool1();
        acPool2 = IGovernor(governor).acPool2();
        acPool3 = IGovernor(governor).acPool3();
        acPool4 = IGovernor(governor).acPool4();
        acPool5 = IGovernor(governor).acPool5();
        acPool6 = IGovernor(governor).acPool6();
    }

    function proxyVote(uint256 _forID) external {
        IacPool(acPool1).voteForProposal(_forID, true);
        IacPool(acPool2).voteForProposal(_forID, true);
        IacPool(acPool3).voteForProposal(_forID, true);
        IacPool(acPool4).voteForProposal(_forID, true);
        IacPool(acPool5).voteForProposal(_forID, true);
        IacPool(acPool6).voteForProposal(_forID, true);
    }

    function proxySetDelegate(address _forWallet) external {
        IacPool(acPool1).setDelegate(_forWallet, true);
        IacPool(acPool2).setDelegate(_forWallet, true);
        IacPool(acPool3).setDelegate(_forWallet, true);
        IacPool(acPool4).setDelegate(_forWallet, true);
        IacPool(acPool5).setDelegate(_forWallet, true);
        IacPool(acPool6).setDelegate(_forWallet, true);
    }
}
