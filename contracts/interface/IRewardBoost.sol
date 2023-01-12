// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface IRewardBoost {
    event AddVotes(
        uint256 _type,
        uint256 proposalID,
        address indexed voter,
        uint256 tokensSacrificed,
        bool _for
    );
    event CancleFibonaccening(uint256 proposalID, address indexed enforcer);
    event ChangeGovernor(address newGovernor);
    event EndFibonaccening(uint256 proposalID, address indexed enforcer);
    event EnforceProposal(
        uint256 _type,
        uint256 proposalID,
        address indexed enforcer,
        bool isSuccess
    );
    event InitiateProposeGrandFibonaccening(
        uint256 proposalID,
        uint256 depositingTokens,
        uint256 eventDate,
        uint256 finalSupply,
        address indexed enforcer,
        uint256 delay
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ProposeFibonaccening(
        uint256 proposalID,
        uint256 valueSacrificedForVote,
        uint256 startTime,
        uint256 durationInBlocks,
        uint256 newRewardPerBlock,
        address indexed enforcer,
        uint256 delay
    );
    event RebalanceInflation(uint256 newRewardPerBlock);

    function calculateUpcomingRewardPerBlock() external view returns (uint256);

    function cancleFibonaccening(uint256 proposalID) external;

    function changeGovernor() external;

    function creditContract() external view returns (address);

    function delayBetweenEvents() external view returns (uint256);

    function desiredSupplyAfterGrandFibonaccening()
        external
        view
        returns (uint256);

    function eligibleGrandFibonaccening() external view returns (bool);

    function endFibonaccening() external;

    function expireLastPrintGrandFibonaccening() external;

    function expiredGrandFibonaccening() external view returns (bool);

    function fibonacceningActivatedBlock() external view returns (uint256);

    function fibonacceningActiveID() external view returns (uint256);

    function fibonacceningProposals(uint256)
        external
        view
        returns (
            bool valid,
            uint256 firstCallTimestamp,
            uint256 valueSacrificedForVote,
            uint256 valueSacrificedAgainst,
            uint256 delay,
            uint256 rewardPerBlock,
            uint256 duration,
            uint256 startTime
        );

    function goldenRatio() external view returns (uint256);

    function grandEventLength() external view returns (uint256);

    function grandFibonacceningActivated() external view returns (bool);

    function grandFibonacceningEnforce(uint256 proposalID) external;

    function grandFibonacceningProposals(uint256)
        external
        view
        returns (
            bool valid,
            uint256 eventDate,
            uint256 firstCallTimestamp,
            uint256 valueSacrificedForVote,
            uint256 valueSacrificedAgainst,
            uint256 delay,
            uint256 finalSupply
        );

    function grandFibonacceningRunning() external;

    function initiateProposeGrandFibonaccening(
        uint256 depositingTokens,
        uint256 eventDate,
        uint256 finalSupply,
        uint256 delay
    ) external;

    function isGrandFibonacceningReady() external;

    function isRunningGrand() external view returns (bool);

    function lastCallFibonaccening() external view returns (uint256);

    function leverPullFibonaccening(uint256 proposalID) external;

    function masterchef() external view returns (address);

    function owner() external view returns (address);

    function proposeFibonaccening(
        uint256 depositingTokens,
        uint256 newRewardPerBlock,
        uint256 durationInBlocks,
        uint256 startTimestamp,
        uint256 delay
    ) external;

    function rebalanceInflation() external;

    function renounceOwnership() external;

    function setMasterchef() external;

    function startLastPrintGrandFibonaccening() external;

    function syncCreditContract() external;

    function targetBlock() external view returns (uint256);

    function token() external view returns (address);

    function tokensForBurn() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updateDelayBetweenEvents(uint256 _delay) external;

    function updateGrandEventLength(uint256 _length) external;

    function vetoFibonaccening(uint256 proposalID) external;

    function vetoProposeGrandFibonaccening(uint256 proposalID) external;

    function voteFibonacceningN(
        uint256 proposalID,
        uint256 withTokens,
        bool withAction
    ) external;

    function voteFibonacceningY(uint256 proposalID, uint256 withTokens)
        external;

    function voteGrandFibonacceningN(
        uint256 proposalID,
        uint256 withTokens,
        bool withAction
    ) external;

    function voteGrandFibonacceningY(uint256 proposalID, uint256 withTokens)
        external;
		
	function proposalLengths() external view returns(uint256)
}
