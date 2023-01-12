// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface IConsensus {
    event AddVotes(
        uint256 _type,
        uint256 proposalID,
        address indexed voter,
        uint256 tokensSacrificed,
        bool _for
    );
    event ChangeGovernor(
        uint256 proposalID,
        address indexed enforcer,
        bool status
    );
    event EnforceDelay(uint256 consensusProposalID, address indexed enforcer);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ProposalAgainstCommonEnemy(
        uint256 HaltID,
        uint256 consensusProposalID,
        uint256 startTimestamp,
        uint256 delayInSeconds,
        address indexed enforcer
    );
    event ProposeGovernor(
        uint256 proposalID,
        address newGovernor,
        address indexed enforcer
    );
    event RemoveDelay(uint256 consensusProposalID, address indexed enforcer);
    event TreasuryEnforce(
        uint256 proposalID,
        address indexed enforcer,
        bool isSuccess
    );
    event TreasuryProposal(
        uint256 proposalID,
        uint256 sacrificedTokens,
        address tokenAddress,
        address recipient,
        uint256 amount,
        uint256 consensusVoteID,
        address indexed enforcer,
        uint256 delay
    );

    function acPool1() external view returns (address);

    function acPool2() external view returns (address);

    function acPool3() external view returns (address);

    function acPool4() external view returns (address);

    function acPool5() external view returns (address);

    function acPool6() external view returns (address);

    function approveTreasuryTransfer(uint256 proposalID) external;

    function changeGovernor(uint256 proposalID) external;

    function changeGovernor() external;

    function consensusProposal(uint256)
        external
        view
        returns (
            uint16 typeOfChange,
            address beneficiaryAddress,
            uint256 timestamp
        );

    function creditContract() external view returns (address);

    function enforceDelay(uint256 fibonacciHaltID) external;

    function enforceGovernor(uint256 proposalID) external;

    function goldenRatio() external view returns (uint256);

    function governorCount() external view returns (uint256);

    function haltProposal(uint256)
        external
        view
        returns (
            bool valid,
            bool enforced,
            uint256 consensusVoteID,
            uint256 startTimestamp,
            uint256 delayInSeconds
        );

    function highestConsensusVotes(uint256) external view returns (uint256);

    function initiateTreasuryTransferProposal(
        uint256 depositingTokens,
        address tokenAddress,
        address recipient,
        uint256 amountToSend,
        uint256 delay
    ) external;

    function isGovInvalidated(address)
        external
        view
        returns (bool isInvalidated, bool hasPassed);

    function killTreasuryTransferProposal(uint256 proposalID) external;

    function owner() external view returns (address);

    function proposeGovernor(address _newGovernor) external;

    function removeDelay(uint256 haltProposalID) external;

    function renounceOwnership() external;

    function syncCreditContract() external;

    function token() external view returns (address);

    function tokensCastedPerVote(uint256 _forID)
        external
        view
        returns (uint256);

    function totalDTXStaked() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function treasuryProposal(uint256)
        external
        view
        returns (
            bool valid,
            uint256 firstCallTimestamp,
            uint256 valueSacrificedForVote,
            uint256 valueSacrificedAgainst,
            uint256 delay,
            address tokenAddress,
            address beneficiary,
            uint256 amountToSend,
            uint256 consensusProposalID
        );

    function treasuryRequestsCount() external view returns (uint256);

    function uniteAgainstTheCommonEnemy(
        uint256 startTimestamp,
        uint256 delayInSeconds
    ) external;

    function updateHighestConsensusVotes(uint256 consensusID) external;

    function updatePools() external;

    function vetoGovernor(uint256 proposalID, bool _withUpdate) external;

    function vetoGovernor2(uint256 proposalID, bool _withUpdate) external;

    function vetoTreasuryTransferProposal(uint256 proposalID) external;

    function voteTreasuryTransferProposalN(
        uint256 proposalID,
        uint256 withTokens,
        bool withAction
    ) external;

    function voteTreasuryTransferProposalY(
        uint256 proposalID,
        uint256 withTokens
    ) external;
	
	function proposalLengths() external view returns(uint256)
}
