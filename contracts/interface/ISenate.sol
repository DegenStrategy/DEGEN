// SPDX-License-Identifier: NONE
pragma solidity >=0.7.0 <0.9.0;

interface ISenate {
    event AddSenator(address senator);
    event AddVote(address voter, uint256 proposalId);
    event RemoveSenator(address senator);
    event RemoveVote(address voter, uint256 proposalId);

    function addSenator(address _newSenator) external;

    function addedSenator(address) external view returns (bool);

    function expandSenate(address _newSenator) external;

    function expellSenator(address _senator) external;

    function grantVotingCredit() external;

    function isSenator(address) external view returns (bool);

    function lastTotalPublished() external view returns (uint256);

    function lastVotingCreditGrant() external view returns (uint256);

    function massAdd(address[] memory _senators) external;

    function maxSenators() external view returns (uint256);

    function minSenators() external view returns (uint256);

    function owner() external view returns (address);

    function removeVote(uint256 proposalId) external;

    function selfReplaceSenator(address _newSenator) external;

    function senatorCount() external view returns (uint256);

    function senatorVotes(address, uint256) external view returns (uint256);

    function senators(uint256) external view returns (address);

    function setSenatorCount(uint256 _min, uint256 _max) external;

    function toUint(address self) external pure returns (uint256);

    function token() external view returns (address);

    function vetoProposal(
        uint256 consensusProposalId,
        uint256 treasuryProposalId
    ) external;

    function viewSenators() external view returns (address[] memory);

    function vote(uint256 proposalId) external;

    function votesForProposal(uint256) external view returns (uint256);
}
