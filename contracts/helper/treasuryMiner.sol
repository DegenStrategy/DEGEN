// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IVoting.sol";

contract TreasuryMiner {
    address public immutable token = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public acPool6 = 0xf3E82f4123d4262a2baEC25b03652f3932A91739;

    bool public canWithdraw = false;
    bool public withdrawalStarted = false;
    uint256 public withdrawalStartedTime = 0;

    uint256 public haltProposalStartingId = 10000000000000; //arbitrary starting proposal ID

    address public immutable votingCreditContract = 0xCF14DbcfFA6E99A444539aBbc9aE273a7bb5d75A;

    constructor() {}

    function startMining() external {
        require(!canWithdraw, "mining ended");
        uint256 _tokenBalance = IDTX(token).balanceOf(address(this));
        require(_tokenBalance >= 5000000 * 1e18, "Miner requires a minimum of 5M tokens");
        IacPool(acPool6).deposit(_tokenBalance);
    }

    function emergencyWithdraw() external {
        require(!canWithdraw, "withdrawal already enabled");
        if(!withdrawalStarted) {
            require(IVoting(votingCreditContract).burnedForId(haltProposalStartingId) > 5000000 * 1e18, "insufficient burned voting credit; 5M required");   
            withdrawalStarted = true;
            withdrawalStartedTime = block.timestamp;
        } else {
            require(block.timestamp > withdrawalStartedTime + 48 hours, "must wait 48hours");// after 20 hours
                if(IVoting(votingCreditContract).burnedForId(haltProposalStartingId) >
                                    IVoting(votingCreditContract).burnedForId(haltProposalStartingId + 1)) {
                    canWithdraw = true;
                } else {
                    withdrawalStarted = false;
                }
            }
        }
    

    function withdrawToken(address _token) external {
        require(canWithdraw, "Withdrawal not allowed");
        require(IDTX(_token).transfer(treasury(), IDTX(_token).balanceOf(address(this))));
    }

    function withdrawWrongToken(address _token) external {
        require(_token != token, "Withdrawal not allowed");
        require(IDTX(_token).transfer(treasury(), IDTX(_token).balanceOf(address(this))));
    }

    function endStake(uint256 _stakeId) external {
        require(canWithdraw, "Withdrawal not allowed");
        IacPool(acPool6).withdrawAll(_stakeId);
        require(IDTX(token).transfer(treasury(), IDTX(token).balanceOf(address(this))));
    }

    function governor() public view returns (address) {
        return IDTX(token).governor();
    }

    function treasury() public view returns (address) {
        return IGovernor(governor()).treasuryWallet();
    }
}

