// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface IGovernor {
    event EnforceGovernor(address _newGovernor, address indexed enforcer);
    event GiveRolloverBonus(
        address recipient,
        uint256 amount,
        address poolInto
    );
    event Harvest(address indexed sender, uint256 callFee);
    event Multisig(
        address signer,
        address newGovernor,
        bool sign,
        uint256 idToVoteFor
    );
    event SetInflation(uint256 rewardPerBlock);
    event TransferOwner(address newOwner, uint256 timestamp);

    function acPool1() external view returns (address);

    function acPool1ID() external view returns (uint256);

    function acPool2() external view returns (address);

    function acPool2ID() external view returns (uint256);

    function acPool3() external view returns (address);

    function acPool3ID() external view returns (uint256);

    function acPool4() external view returns (address);

    function acPool4ID() external view returns (uint256);

    function acPool5() external view returns (address);

    function acPool5ID() external view returns (uint256);

    function acPool6() external view returns (address);

    function acPool6ID() external view returns (uint256);

    function alreadySigned(address, address) external view returns (bool);

    function basicContract() external view returns (address);

    function blocksPerSecond() external view returns (uint256);

    function burnTokens(uint256 amount) external;

    function calculateAverageBlockTime() external;

    function changeGovernorActivated() external view returns (bool);

    function consensusContract() external view returns (address);

    function costToVote() external view returns (uint256);

    function countingBlocks() external view returns (bool);

    function creditContract() external view returns (address);

    function delayBeforeEnforce() external view returns (uint256);

    function delayFibonacci(bool _arg) external;

    function durationForCalculation() external view returns (uint256);

    function eligibleNewGovernor() external view returns (address);

    function enforceGovernor() external;

    function eventFibonacceningActive() external view returns (bool);

    function farmContract() external view returns (address);

    function fibonacceningContract() external view returns (address);

    function fibonacciDelayed() external view returns (bool);

    function getRollBonus(address _bonusForPool)
        external
        view
        returns (uint256);

    function goldenRatio() external view returns (uint256);

    function governorRejected() external;

    function harvest() external;

    function harvestAll() external;

    function isInflationStatic() external view returns (bool);

    function lastBlockHeight() external view returns (uint256);

    function lastHarvestedTime() external view returns (uint256);

    function lastRegularReward() external view returns (uint256);

    function masterchef() external view returns (address);

    function maxDelay() external view returns (uint256);

    function minDelay() external view returns (uint256);

    function newGovernorBlockDelay() external view returns (uint256);

    function newGovernorRequestBlock() external view returns (uint256);

    function nftAllocationContract() external view returns (address);

    function nftStakingContract() external view returns (address);

    function nftStakingPoolID() external view returns (uint256);

    function nftWallet() external view returns (address);

    function pendingHarvestRewards() external view returns (uint256);

    function postGrandFibIncreaseCount() external;

    function rebalanceFarms() external;

    function rebalancePools() external;

    function recordTimeStart() external view returns (uint256);

    function rememberReward() external;

    function setActivateFibonaccening(bool _arg) external;

    function setCallFee(address _acPool, uint256 _newCallFee) external;

    function setGovernorTax(uint256 _amount) external;

    function setInflation(uint256 rewardPerBlock) external;

    function setNewGovernor(address beneficiary) external;

    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external;

    function setThresholdFibonaccening(uint256 newThreshold) external;

    function signaturesConfirmed(address, uint256)
        external
        view
        returns (address);

    function stakeRolloverBonus(
        address _toAddress,
        address _depositToPool,
        uint256 _bonusToPay,
        uint256 _stakeID
    ) external;

    function startCountingBlocks() external;

    function thresholdFibonaccening() external view returns (uint256);

    function token() external view returns (address);

    function totalFibonacciEventsAfterGrand() external view returns (uint256);

    function transferCollectedFees(address _tokenContract) external;

    function transferRewardBoostThreshold() external;

    function transferToTreasury(uint256 amount) external;

    function treasuryRequest(
        address _tokenAddr,
        address _recipient,
        uint256 _amountToSend
    ) external;

    function treasuryWallet() external view returns (address);

    function updateAllPools() external;

    function updateCostToVote(uint256 newCostToVote) external;

    function updateDelayBeforeEnforce(uint256 newDelay) external;

    function updateDelayBetweenEvents(uint256 _amount) external;

    function updateDurationForCalculation(uint256 _newDuration) external;

    function updateGovernorChangeDelay() external;

    function updateGrandEventLength(uint256 _amount) external;

    function updateRolloverBonus(address _forPool, uint256 _bonus) external;
}

