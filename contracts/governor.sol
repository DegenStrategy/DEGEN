// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IGovernor.sol";
import "./interface/IMasterChef.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IVoting.sol";
import "./interface/IRewardBoost.sol";
import "./interface/IacPool.sol";
import "./interface/ITreasury.sol";
import "./interface/IVault.sol";


    /**
     * DTX governor is a decentralized masterchef governed by it's users
     * Works as a decentralized cryptocurrency with no third-party control
     * Effectively creating a DAO through time-deposits
     *
     * In order to earn staking rewards, users must lock up their tokens.
     * Certificates of deposit or time deposit are the biggest market in the world
     * The longer the lockup period, the higher the rewards(APY) and voting power 
     * The locked up stakers create the governance council, through which
     * the protocol can be upgraded in a decentralized manner.
     *
     * Users are utilized as oracles through on-chain voting regulating the entire system(events,
     * rewards, APYs, fees, bonuses,...)
     * The token voting is overpowered by the consensus mechanism(locked up stakers)
     *
     * It is a real DAO creating an actual decentralized finance ecosystem
    */

    
contract DTXgovernor {
    
    uint256 public immutable goldenRatio = 1618; //1.618 is the golden ratio
    address public immutable token = ENTERNEWTOKEN; //DTX token
    
    //masterchef address
    address public immutable masterchef = ENTERNEWCHEF;
	
    address public immutable consensusContract = ;
    address public immutable farmContract = ;
    address public immutable fibonacceningContract = ; //reward boost contract
    address public immutable basicContract = ;
	address public immutable senateContract = ;
	
	address public immutable creditContract = ;
	
	address public immutable nftStakingContract = ;
	address public immutable nftAllocationContract = ;
    
    //Addresses for treasuryWallet and NFT wallet
    address public treasuryWallet = ;
    address public nftWallet = ;
    
    //addresses for time-locked deposits(autocompounding pools)
    address public immutable acPool1 = ;
    address public immutable acPool2 = ;
    address public immutable acPool3 = ;
    address public immutable acPool4 = ;
    address public immutable acPool5 = ;
    address public immutable acPool6 = ;
        
    //pool ID in the masterchef for respective Pool address and dummy token
    uint256 public immutable acPool1ID = 0;
    uint256 public immutable acPool2ID = 1;
    uint256 public immutable acPool3ID = 2;
    uint256 public immutable acPool4ID = 3;
    uint256 public immutable acPool5ID = 4;
    uint256 public immutable acPool6ID = 5;
	
	uint256 public immutable nftStakingPoolID = 10;
	
	address public immutable plsVault = ;
	address public immutable plsxVault = ;
	address public immutable hexVault = ;
	address public immutable incVault = ;
	address public immutable lp1Vault = ; // PLS LP
	address public immutable lp2Vault = ; // USD LP
	address public immutable lp3Vault = ; // HEX LP
	address public immutable lp4Vault = ; // PLSX LP
    
    mapping(address => uint256) private _rollBonus;
	
	uint256 public newGovernorBlockDelay = 189000; //in blocks (roughly 5 days at beginning)
    
    uint256 public costToVote = 500000 * 1e18;  // 500K coins. All proposals are valid unless rejected. This is a minimum to prevent spam
    uint256 public delayBeforeEnforce = 3 days; //minimum number of TIME between when proposal is initiated and executed
    
    //fibonaccening event can be scheduled once minimum threshold of tokens have been collected
    uint256 public thresholdFibonaccening = 10000000000 * 1e18; //10B coins
    
    //delays for Fibonnaccening(Reward Boost) Events
    uint256 public immutable minDelay = 1 days; // has to be called minimum 1 day in advance
    uint256 public immutable maxDelay = 31 days; //1month.. is that good? i think yes
    
    uint256 public lastRegularReward = 42069000000000000000000; //remembers the last reward used(outside of boost)
    bool public eventFibonacceningActive = true; // prevent some functions if event is active ..threshold and durations for fibonaccening
    
    uint256 public blocksPerSecond = 100000; // divide by a million
    uint256 public durationForCalculation= 12 hours; //period used to calculate block time
    uint256  public lastBlockHeight; //block number when counting is activated
    uint256 public recordTimeStart; //timestamp when counting is activated
    bool public countingBlocks;

	bool public isInflationStatic; // if static, inflation stays perpetually at 1.618% annually. If dynamic, it reduces by 1.618% on each reward boost
    uint256  public totalFibonacciEventsAfterGrand; //used for rebalancing inflation after Grand Fib
    
    uint256 public newGovernorRequestBlock;
    address public eligibleNewGovernor; //used for changing smart contract
    bool public changeGovernorActivated;

	bool public fibonacciDelayed; //used to delay fibonaccening events through vote
	
	uint256 public lastHarvestedTime;

    event SetInflation(uint256 rewardPerBlock);
    event TransferOwner(address newOwner, uint256 timestamp);
    event EnforceGovernor(address _newGovernor, address indexed enforcer);
    event GiveRolloverBonus(address recipient, uint256 amount, address poolInto);
	event Harvest(address indexed sender, uint256 callFee);
	event Multisig(address signer, address newGovernor, bool sign, uint256 idToVoteFor);
    
    constructor(
		address _acPool1,
		address _acPool2,
		address _acPool3,
		address _acPool4,
		address _acPool5,
		address _acPool6) {
			_rollBonus[_acPool1] = 75;
			_rollBonus[_acPool2] = 100;
			_rollBonus[_acPool3] = 150;
			_rollBonus[_acPool4] = 250;
			_rollBonus[_acPool5] = 350;
			_rollBonus[_acPool6] = 500;
    }    

    

    /**
     * Calculates average block time
     * No decimals so we keep track of "100blocks" per second
	 * It will be used in the future to keep inflation static, while block production can be dynamic
	 * (bitcoin adjusts to 1 block per 10minutes, DTX inflation is dependant on the production of blocks on Pulsechain which can vary)
     */
    function startCountingBlocks() external {
        require(!countingBlocks, "already counting blocks");
        countingBlocks = true;
        lastBlockHeight = block.number;
        recordTimeStart = block.timestamp;
    } 
    function calculateAverageBlockTime() external {
        require(countingBlocks && (recordTimeStart + durationForCalculation) <= block.timestamp);
        blocksPerSecond = 1000000 * (block.number - lastBlockHeight) / (block.timestamp - recordTimeStart);
        countingBlocks = false;
    }
    
    function getRollBonus(address _bonusForPool) external view returns (uint256) {
        return _rollBonus[_bonusForPool];
    }
    
   
   
     /**
     * Rebalances Pools and allocates rewards in masterchef
     * Pools with higher time-lock must always pay higher rewards in relative terms
     * Eg. for 1DTX staked in the pool 6, you should always be receiving
     * 50% more rewards compared to staking in pool 4
     * 
     * QUESTION: should we create a modifier to prevent rebalancing during inflation events?
     * Longer pools compound on their interests and earn much faster?
     * On the other hand it could also be an incentive to hop to pools with longer lockup
	 * Could also make it changeable through voting
     */
    function rebalancePools() public {
    	uint256 balancePool1 = IacPool(acPool1).balanceOf();
    	uint256 balancePool2 = IacPool(acPool2).balanceOf();
    	uint256 balancePool3 = IacPool(acPool3).balanceOf();
    	uint256 balancePool4 = IacPool(acPool4).balanceOf();
    	uint256 balancePool5 = IacPool(acPool5).balanceOf();
    	uint256 balancePool6 = IacPool(acPool6).balanceOf();
    	
   	    uint256 total = balancePool1 + balancePool2 + balancePool3 + balancePool4 + balancePool5 + balancePool6;
    	
    	IMasterChef(masterchef).set(acPool1ID, (balancePool1 * 20000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool2ID, (balancePool2 * 30000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool3ID, (balancePool3 * 45000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool4ID, (balancePool4 * 100000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool5ID, (balancePool5 * 130000 / total), 0, false);
    	IMasterChef(masterchef).set(acPool6ID, (balancePool6 * 150000 / total), 0, false); 
    	
    	//equivalent to massUpdatePools() in masterchef, but we loop just through relevant pools
    	IMasterChef(masterchef).updatePool(acPool1ID);
    	IMasterChef(masterchef).updatePool(acPool2ID); 
    	IMasterChef(masterchef).updatePool(acPool3ID); 
    	IMasterChef(masterchef).updatePool(acPool4ID); 
    	IMasterChef(masterchef).updatePool(acPool5ID); 
    	IMasterChef(masterchef).updatePool(acPool6ID); 
    }
	
	function harvestAll() public {
		IacPool(acPool1).harvest();
		IacPool(acPool2).harvest();
		IacPool(acPool3).harvest();
		IacPool(acPool4).harvest();
		IacPool(acPool5).harvest();
		IacPool(acPool6).harvest();
	}

    /**
     * Harvests from all pools and rebalances rewards
     */
    function harvest() external {
        require(msg.sender == tx.origin, "no proxy/contracts");

        uint256 totalFee = pendingHarvestRewards();

		harvestAll();
        rebalancePools();
		
		lastHarvestedTime = block.timestamp;
	
		require(IERC20(token).transfer(msg.sender, totalFee), "token transfer failed");

		emit Harvest(msg.sender, totalFee);
    }
	
	function pendingHarvestRewards() public view returns (uint256) {
		uint256 totalRewards = IacPool(acPool1).calculateHarvestDTXRewards() + IacPool(acPool2).calculateHarvestDTXRewards() + IacPool(acPool3).calculateHarvestDTXRewards() +
        					IacPool(acPool4).calculateHarvestDTXRewards() + IacPool(acPool5).calculateHarvestDTXRewards() + IacPool(acPool6).calculateHarvestDTXRewards();
		return totalRewards;
	}
    
    /**
     * Mechanism, where the governor gives the bonus 
     * to user for extending(re-commiting) their stake
     * tldr; sends the gift deposit, which resets the timer
     * the pool is responsible for calculating the bonus
     */
    function stakeRolloverBonus(address _toAddress, address _depositToPool, uint256 _bonusToPay, uint256 _stakeID) external {
        require(
            msg.sender == acPool1 || msg.sender == acPool2 || msg.sender == acPool3 ||
            msg.sender == acPool4 || msg.sender == acPool5 || msg.sender == acPool6);
        
        IacPool(_depositToPool).addAndExtendStake(_toAddress, _bonusToPay, _stakeID, 0);
        
        emit GiveRolloverBonus(_toAddress, _bonusToPay, _depositToPool);
    }

    /**
     * Sets inflation in Masterchef
     */
    function setInflation(uint256 rewardPerBlock) external {
        require(msg.sender == fibonacceningContract);
    	IMasterChef(masterchef).updateEmissionRate(rewardPerBlock);

        emit SetInflation(rewardPerBlock);
    }
	
	function rememberReward() external {
		require(msg.sender == fibonacceningContract);
		lastRegularReward = IMasterChef(masterchef).DTXPerBlock();
	}
    
    
    function enforceGovernor() external {
        require(msg.sender == consensusContract);
		require(newGovernorRequestBlock + newGovernorBlockDelay < block.number, "time delay not yet passed");

		IMasterChef(masterchef).setFeeAddress(eligibleNewGovernor);
        IMasterChef(masterchef).dev(eligibleNewGovernor);
        IMasterChef(masterchef).transferOwnership(eligibleNewGovernor); //transfer masterchef ownership
		
		IERC20(token).transfer(eligibleNewGovernor, IERC20(token).balanceOf(address(this))); // send collected DTX tokens to new governor
        
		emit EnforceGovernor(eligibleNewGovernor, msg.sender);
    }
	
    function setNewGovernor(address beneficiary) external {
        require(msg.sender == consensusContract);
        newGovernorRequestBlock = block.number;
        eligibleNewGovernor = beneficiary;
        changeGovernorActivated = true;
    }
	
	function governorRejected() external {
		require(changeGovernorActivated, "not active");
		
		(bool _govInvalidated, ) = IConsensus(consensusContract).isGovInvalidated(eligibleNewGovernor);
		if(_govInvalidated) {
			changeGovernorActivated = false;
		}
	}

	function treasuryRequest(address _tokenAddr, address _recipient, uint256 _amountToSend) external {
		require(msg.sender == consensusContract);
		ITreasury(payable(treasuryWallet)).requestWithdraw(
			_tokenAddr, _recipient, _amountToSend
		);
	}
	
	function updateDurationForCalculation(uint256 _newDuration) external {
	    require(msg.sender == basicContract);
	    durationForCalculation = _newDuration;
	}
	
	function delayFibonacci(bool _arg) external {
	    require(msg.sender == consensusContract);
	    fibonacciDelayed = _arg;
	}
	
	function setActivateFibonaccening(bool _arg) external {
		require(msg.sender == fibonacceningContract);
		eventFibonacceningActive = _arg;
	}

	function setPool(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external {
	    require(msg.sender == farmContract);
	    IMasterChef(masterchef).set(_pid, _allocPoint, _depositFeeBP, _withUpdate);
	}
	
	function setThresholdFibonaccening(uint256 newThreshold) external {
	    require(msg.sender == basicContract);
	    thresholdFibonaccening = newThreshold;
	}
	
	function updateDelayBeforeEnforce(uint256 newDelay) external {
	    require(msg.sender == basicContract);
	    delayBeforeEnforce = newDelay;
	}
	
	function setCallFee(address _acPool, uint256 _newCallFee) external {
	    require(msg.sender == basicContract);
	    IacPool(_acPool).setCallFee(_newCallFee);
	}
	
	function updateCostToVote(uint256 newCostToVote) external {
	    require(msg.sender == basicContract);
	    costToVote = newCostToVote;
	}
	
	function updateRolloverBonus(address _forPool, uint256 _bonus) external {
	    require(msg.sender == basicContract);
		require(_bonus <= 1500, "15% hard limit");
	    _rollBonus[_forPool] = _bonus;
	}

	function updateVault(uint256 _type, uint256 _amount) external {

        require(msg.sender == farmContract);

        if(_type == 0) {
            IVault(plsVault).setDepositFee(_amount);
            IVault(plsxVault).setDepositFee(_amount);
            IVault(hexVault).setDepositFee(_amount);
			IVault(incVault).setDepositFee(_amount);
        } else if(_type == 2) {
            IVault(plsVault).setFundingRate(_amount);
            IVault(plsxVault).setFundingRate(_amount);
            IVault(hexVault).setFundingRate(_amount);
			IVault(incVault).setFundingRate(_amount);
        } else if(_type == 3) {
            IVault(plsVault).setRefShare1(_amount);
            IVault(plsxVault).setRefShare1(_amount);
            IVault(hexVault).setRefShare1(_amount);
			IVault(incVault).setRefShare1(_amount);
        } else if(_type == 4) {
            IVault(plsVault).setRefShare2(_amount);
            IVault(plsxVault).setRefShare2(_amount);
            IVault(hexVault).setRefShare2(_amount);
			IVault(incVault).setRefShare2(_amount);
        } 
    }
	
	function setGovernorTax(uint256 _amount) external {
		require(msg.sender == farmContract);
		IMasterChef(masterchef).setGovernorFee(_amount);
	}
	
	function transferRewardBoostThreshold() external {
		require(msg.sender == fibonacceningContract);
		
		IERC20(token).transfer(fibonacceningContract, thresholdFibonaccening);
	}
	
	function burnTokens(uint256 amount) external {
		require(msg.sender == farmContract);
		
		IDTX(token).burn(amount);
	}
	
	function transferToTreasury(uint256 amount) external {
		require(msg.sender == farmContract);
		
		IERC20(token).transfer(treasuryWallet, amount);
	}
	
	function postGrandFibIncreaseCount() external {
		require(msg.sender == fibonacceningContract);
		totalFibonacciEventsAfterGrand++;
	}
	
	function updateDelayBetweenEvents(uint256 _amount) external {
	    require(msg.sender == basicContract);
		IRewardBoost(fibonacceningContract).updateDelayBetweenEvents(_amount);
	}
	function updateGrandEventLength(uint256 _amount) external {
	    require(msg.sender == basicContract);
		IRewardBoost(fibonacceningContract).updateGrandEventLength(_amount);
	}
	    
	
    /**
     * Transfers collected fees into treasury wallet(but not DTX...for now)
     */
    function transferCollectedFees(address _tokenContract) external {
        require(msg.sender == tx.origin);
		require(_tokenContract != token, "not DTX!");
		
        uint256 amount = IERC20(_tokenContract).balanceOf(address(this));
        
        IERC20(_tokenContract).transfer(treasuryWallet, amount);
    }
	
	
	/*
	 * newGovernorBlockDelay is the delay during which the governor proposal can be voted against
	 * As the time passes, changes should take longer to enforce(greater security)
	 * Prioritize speed and efficiency at launch. Prioritize security once established
	 * Delay increases by 2500 blocks(roughly 1.6hours) per each day after launch
	 * Delay starts at 189000 blocks(roughly 5 days)
	 * After a month, delay will be roughly 7 days (increases 2days/month)
	 * After a year, 29 days. After 2 years, 53 days,...
	 * Can be ofcourse changed by replacing governor contract
	 */
	function updateGovernorChangeDelay() external {
		newGovernorBlockDelay = 189000 + (((block.timestamp - 1654041600) / 86400) * 2500);
	}
    
}  
