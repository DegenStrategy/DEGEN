// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "./interface/IGovernor.sol";
import "./interface/IMasterChef.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IVoting.sol";


// reward boost contract
// tldr; A reward boost is called 'Fibonaccening', could be compared to Bitcoin halvening
// When A threshold of tokens are collected, a reward boost event can be scheduled
// During the event there is a period of boosted rewards
// After the event ends, the tokens are burned and the global inflation is reduced
contract DTXrewardBoost {    
    struct FibonacceningProposal {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 rewardPerBlock;
        uint256 duration;
        uint256 startTime;
    }
    struct ProposeGrandFibonaccening{
        bool valid;
        uint256 eventDate; 
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 finalSupply;
    }
    
    FibonacceningProposal[] public fibonacceningProposals;
    ProposeGrandFibonaccening[] public grandFibonacceningProposals;

    //WARNING: careful where we are using 1e18 and where not
    uint256 public immutable goldenRatio = 1618; //1.618 is the golden ratio
    IERC20 public immutable token; //DTX token
	
    
    //masterchef address
    address public masterchef;
	
	address public creditContract;
    
    uint256 public lastCallFibonaccening; //stores timestamp of last grand fibonaccening event
    
    bool public eligibleGrandFibonaccening; // when big event is ready
    bool public grandFibonacceningActivated; // if upgrading the contract after event, watch out this must be true
    uint256 public desiredSupplyAfterGrandFibonaccening; // Desired supply to reach for Grand Fib Event
    
    uint256 public targetBlock; // used for calculating target block
    bool public isRunningGrand; //we use this during Grand Fib Event

    uint256 public fibonacceningActiveID;
    uint256 public fibonacceningActivatedBlock;
    
    bool public expiredGrandFibonaccening;
    
    uint256 public tokensForBurn; //tokens we draw from governor to burn for fib event

	uint256 public grandEventLength = 14 * 24 * 3600; // default Duration for the Grand Fibonaccening(the time in which 61.8% of the supply is printed)
	uint256 public delayBetweenEvents = 48 * 3600; // delay between when grand events can be triggered(default 48hrs)

    event ProposeFibonaccening(uint256 proposalID, uint256 valueSacrificedForVote, uint256 startTime, uint256 durationInBlocks, uint256 newRewardPerBlock , address indexed enforcer, uint256 delay);

    event EndFibonaccening(uint256 proposalID, address indexed enforcer);
    event CancleFibonaccening(uint256 proposalID, address indexed enforcer);
    
    event RebalanceInflation(uint256 newRewardPerBlock);
    
    event InitiateProposeGrandFibonaccening(uint256 proposalID, uint256 depositingTokens, uint256 eventDate, uint256 finalSupply, address indexed enforcer, uint256 delay);
	
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);
    
    event ChangeGovernor(address newGovernor);
	
	constructor (IERC20 _DTX, address _masterchef) {
		token = _DTX;
		masterchef = _masterchef;
		
		fibonacceningProposals.push(
		    FibonacceningProposal(true, 0, 1e40, 0, 0, 169*1e21, 185000, 1654097100)
		    );
	}
    
    
    /**
     * Regulatory process for scheduling a "fibonaccening event"
    */    
    function proposeFibonaccening(uint256 depositingTokens, uint256 newRewardPerBlock, uint256 durationInBlocks, uint256 startTimestamp, uint256 delay) external {
        require(depositingTokens >= IGovernor(owner()).costToVote(), "costs to submit decisions");
        require(IERC20(token).balanceOf(owner()) >= IGovernor(owner()).thresholdFibonaccening(), "need to collect penalties before calling");
        require(!(IGovernor(owner()).eventFibonacceningActive()), "Event already running");
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
        require(
            startTimestamp > block.timestamp + delay + (24*3600) + IGovernor(owner()).delayBeforeEnforce() && 
            startTimestamp - block.timestamp <= 21 days, "max 21 days"); 
        require(
            (newRewardPerBlock * durationInBlocks) < (IERC20(token).totalSupply() * 23 / 100),
            "Safeguard: Can't print more than 23% of tokens in single event"
        );
		require(newRewardPerBlock > goldenRatio || (!isRunningGrand && expiredGrandFibonaccening),
					"can't go below goldenratio"); //would enable grand fibonaccening
		//duration(in blocks) must be lower than amount of blocks mined in 30days(can't last more than roughly 30days)
		//30(days)*24(hours)*3600(seconds)  = 2592000
		uint256 amountOfBlocksIn30Days = 2592 * IGovernor(owner()).blocksPerSecond() / 1000;
		require(durationInBlocks <= amountOfBlocksIn30Days, "maximum 30days duration");
    
		IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
        fibonacceningProposals.push(
            FibonacceningProposal(true, block.timestamp, depositingTokens, 0, delay, newRewardPerBlock, durationInBlocks, startTimestamp)
            );
    	
    	emit ProposeFibonaccening(fibonacceningProposals.length - 1, depositingTokens, startTimestamp, durationInBlocks, newRewardPerBlock, msg.sender, delay);
    }
	function voteFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(fibonacceningProposals[proposalID].valid, "invalid");
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay + IGovernor(owner()).delayBeforeEnforce() > block.timestamp, "past the point of no return"); 
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		fibonacceningProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(fibonacceningProposals[proposalID].valid, "invalid");
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay + IGovernor(owner()).delayBeforeEnforce() > block.timestamp, "past the point of no return"); 
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		fibonacceningProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoFibonaccening(proposalID); }
		
		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoFibonaccening(uint256 proposalID) public {
    	require(fibonacceningProposals[proposalID].valid == true, "Invalid proposal"); 
		require(fibonacceningProposals[proposalID].firstCallTimestamp + fibonacceningProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(fibonacceningProposals[proposalID].valueSacrificedForVote < fibonacceningProposals[proposalID].valueSacrificedAgainst, "needs more votes");
 
    	fibonacceningProposals[proposalID].valid = false; 
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }

    /**
     * Activates a valid fibonaccening event
     * 
    */
    function leverPullFibonaccening(uint256 proposalID) public {
		require(!(IGovernor(owner()).fibonacciDelayed()), "event has been delayed");
        require(
            IERC20(token).balanceOf(owner()) >= IGovernor(owner()).thresholdFibonaccening(),
            "needa collect penalties");
    	require(fibonacceningProposals[proposalID].valid == true, "invalid proposal");
    	require(block.timestamp >= fibonacceningProposals[proposalID].startTime, "can only start when set");
    	require(!(IGovernor(owner()).eventFibonacceningActive()), "already active");
		require(!grandFibonacceningActivated || (expiredGrandFibonaccening && !isRunningGrand), "not available during the grand boost event");
    	
    	if(fibonacceningProposals[proposalID].valueSacrificedForVote >= fibonacceningProposals[proposalID].valueSacrificedAgainst) {
			tokensForBurn = IGovernor(owner()).thresholdFibonaccening();
			IGovernor(owner()).transferRewardBoostThreshold();
			
			IGovernor(owner()).rememberReward(); // remembers last regular rewar(before boost)
			IGovernor(owner()).setInflation(fibonacceningProposals[proposalID].rewardPerBlock);
			
			fibonacceningProposals[proposalID].valid = false;
			fibonacceningActiveID = proposalID;
			fibonacceningActivatedBlock = block.number;
			IGovernor(owner()).setActivateFibonaccening(true);
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
		} else {
			vetoFibonaccening(proposalID);
		}
    }
    
     /**
     * Ends fibonaccening event 
     * sets new inflation  
     * burns the tokens
    */
    function endFibonaccening() external {
        require(IGovernor(owner()).eventFibonacceningActive(), "no active event");
        require(
            block.number >= fibonacceningActivatedBlock + fibonacceningProposals[fibonacceningActiveID].duration, 
            "not yet expired"
           ); 
        
        uint256 newAmount = calculateUpcomingRewardPerBlock();
        
        IGovernor(owner()).setInflation(newAmount);
        IGovernor(owner()).setActivateFibonaccening(false);
        
    	IDTX(address(token)).burn(tokensForBurn); // burns the tokens - "fibonaccening" sacrifice
		
		//if past 'grand fibonaccening' increase event count
		if(!isRunningGrand && expiredGrandFibonaccening) {
			IGovernor(owner()).postGrandFibIncreaseCount();
		}
		
    	emit EndFibonaccening(fibonacceningActiveID, msg.sender);
    }
    

    /**
     * In case we have multiple valid fibonaccening proposals
     * When the event is enforced, all other valid proposals can be invalidated
     * Just to clear up the space
    */
    function cancleFibonaccening(uint256 proposalID) external {
        require(IGovernor(owner()).eventFibonacceningActive(), "fibonaccening active required");

        require(fibonacceningProposals[proposalID].valid, "must be valid to negate ofc");
        
        fibonacceningProposals[proposalID].valid = false;
        emit CancleFibonaccening(proposalID, msg.sender);
    }
    
    /**
     * After the Grand Fibonaccening event, the inflation reduces to roughly 1.618% annually
     * On each new Fibonaccening event, it further reduces by Golden ratio(in percentile)
	 *
     * New inflation = Current inflation * ((100 - 1.618) / 100)
     */
    function rebalanceInflation() external {
        require(IGovernor(owner()).totalFibonacciEventsAfterGrand() > 0, "Only after the Grand Fibonaccening event");
        require(!(IGovernor(owner()).eventFibonacceningActive()), "Event is running");
		bool isStatic = IGovernor(owner()).isInflationStatic();
        
		uint256 initialSupply = IERC20(token).totalSupply();
		uint256 _factor = goldenRatio;
		
		// if static, then inflation is 1.618% annually
		// Else the inflation reduces by 1.618%(annually) on each event
		if(!isStatic) {
			for(uint256 i = 0; i < IGovernor(owner()).totalFibonacciEventsAfterGrand(); i++) {
				_factor = _factor * 98382 / 100000; //factor is multiplied * 1000 (number is 1618, when actual factor is 1.618)
			}
		}
		
		// divide by 1000 to turn 1618 into 1.618% (and then divide farther by 100 to convert percentage)
        uint256 supplyToPrint = initialSupply * _factor / 100000; 
		
        uint256 rewardPerBlock = supplyToPrint / (365 * 24 * 36 * IGovernor(owner()).blocksPerSecond() / 10000);
        IGovernor(owner()).setInflation(rewardPerBlock);
       
        emit RebalanceInflation(rewardPerBlock);
    }
    
     /**
     * If inflation is to drop below golden ratio, the grand fibonaccening event is ready
	 * IMPORTANT NOTE: the math for the grand fibonaccening needs a lot of additional checks
	 * It is almost certain that fixes will be required. The event won't happen for quite some time.
	 * Giving enough time for additional fixes and changes to be adapted
     */
    function isGrandFibonacceningReady() external {
		require(!eligibleGrandFibonaccening);
        if((IMasterChef(masterchef).DTXPerBlock() - goldenRatio * 1e18) <= goldenRatio * 1e18) { //we x1000'd the supply so 1e18
            eligibleGrandFibonaccening = true;
        }
    }

    /**
     * The Grand Fibonaccening Event, only happens once
	 * A lot of Supply is printed (x1.618 - x1,000,000)
	 * People like to buy on the way down
	 * People like high APYs
	 * People like to buy cheap coins
	 * Grand Fibonaccening ain't happening for quite some time... 
	 * We could add a requirement to vote through consensus for the "Grand Fibonaccening" to be enforced
     */    
    function initiateProposeGrandFibonaccening(uint256 depositingTokens, uint256 eventDate, uint256 finalSupply, uint256 delay) external {
    	require(eligibleGrandFibonaccening && !grandFibonacceningActivated);
		require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "there is a minimum cost to vote");
		uint256 _totalSupply = IERC20(token).totalSupply();
    	require(finalSupply >= (_totalSupply * 1618 / 1000) && finalSupply <= (_totalSupply * 1000000));
    	require(eventDate > block.timestamp + delay + (7*24*3600) + IGovernor(owner()).delayBeforeEnforce());
    	
    	
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	grandFibonacceningProposals.push(
    	    ProposeGrandFibonaccening(true, eventDate, block.timestamp, depositingTokens, 0, delay, finalSupply)
    	    );
    
        emit EnforceProposal(1, grandFibonacceningProposals.length - 1, msg.sender, true);
    }
	function voteGrandFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(grandFibonacceningProposals[proposalID].valid, "invalid");
		require(grandFibonacceningProposals[proposalID].eventDate - (7*24*3600) > block.timestamp, "past the point of no return"); //can only be cancled up until 7days before event
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		grandFibonacceningProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteGrandFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(grandFibonacceningProposals[proposalID].valid, "invalid");
		require(grandFibonacceningProposals[proposalID].eventDate - (7*24*3600) > block.timestamp, "past the point of no return"); //can only be cancled up until 7days before event
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		grandFibonacceningProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoProposeGrandFibonaccening(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
	/*
	* can be vetto'd during delayBeforeEnforce period.
	* afterwards it can not be cancled anymore
	* but it can still be front-ran by earlier event
	*/
    function vetoProposeGrandFibonaccening(uint256 proposalID) public {
    	require(grandFibonacceningProposals[proposalID].valid, "already invalid");
		require(grandFibonacceningProposals[proposalID].firstCallTimestamp + grandFibonacceningProposals[proposalID].delay + IGovernor(owner()).delayBeforeEnforce() <= block.timestamp, "pending delay");
		require(grandFibonacceningProposals[proposalID].valueSacrificedForVote < grandFibonacceningProposals[proposalID].valueSacrificedAgainst, "needs more votes");

    	grandFibonacceningProposals[proposalID].valid = false;  
    	
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    
	
    function grandFibonacceningEnforce(uint256 proposalID) public {
        require(!grandFibonacceningActivated, "already called");
        require(grandFibonacceningProposals[proposalID].valid && grandFibonacceningProposals[proposalID].eventDate <= block.timestamp, "not yet valid");
		
		address _consensusContract = IGovernor(owner()).consensusContract();
		
		uint256 _totalStaked = IConsensus(_consensusContract).totalDTXStaked();
		
		//to approve grand fibonaccening, more tokens have to be sacrificed for vote ++
		// more stakes(locked shares) need to vote in favor than against it
		//to vote in favor, simply vote for proposal ID of maximum uint256 number - 1
		uint256 _totalVotedInFavor = IConsensus(_consensusContract).tokensCastedPerVote(type(uint256).max - 1);
		uint256 _totalVotedAgainst= IConsensus(_consensusContract).tokensCastedPerVote(type(uint256).max);
		
        require(_totalVotedInFavor >= _totalStaked * 25 / 100
                    || _totalVotedAgainst >= _totalStaked * 25 / 100,
                             "minimum 25% weighted vote required");

		if(grandFibonacceningProposals[proposalID].valueSacrificedForVote >= grandFibonacceningProposals[proposalID].valueSacrificedAgainst
				&& _totalVotedInFavor > _totalVotedAgainst) {
			grandFibonacceningActivated = true;
			grandFibonacceningProposals[proposalID].valid = false;
			desiredSupplyAfterGrandFibonaccening = grandFibonacceningProposals[proposalID].finalSupply;
			
			emit EnforceProposal(1, proposalID, msg.sender, true);
		} else {
			grandFibonacceningProposals[proposalID].valid = false;  
    	
			emit EnforceProposal(1, proposalID, msg.sender, false);
		}
    }
    
    /**
     * Function handling The Grand Fibonaccening
	 *
     */
    function grandFibonacceningRunning() external {
        require(grandFibonacceningActivated && !expiredGrandFibonaccening);
        
        if(isRunningGrand){
            require(block.number >= targetBlock, "target block not yet reached");
            IGovernor(owner()).setInflation(0);
            isRunningGrand = false;
        } else {
			require(!(IGovernor(owner()).fibonacciDelayed()), "event has been delayed");
			uint256 _totalSupply = IERC20(token).totalSupply();
            require(
                ( _totalSupply * goldenRatio * goldenRatio / 1000000) < desiredSupplyAfterGrandFibonaccening, 
                "Last 2 events happen at once"
                );
			// Just a simple implementation that allows max once per day at a certain time
            require(
                (block.timestamp % 86400) / 3600 >= 16 && (block.timestamp % 86400) / 3600 <= 18,
                "can only call between 16-18 UTC"
            );
			require(block.timestamp - lastCallFibonaccening > delayBetweenEvents);
			
			lastCallFibonaccening = block.timestamp;
            uint256 targetedSupply =  _totalSupply * goldenRatio / 1000;
			uint256 amountToPrint = targetedSupply - _totalSupply; // (+61.8%)
            
			//printing the amount(61.8% of supply) in uint256(grandEventLength) seconds ( blocks in second are x100 )
            uint256 rewardPerBlock = amountToPrint / (grandEventLength * IGovernor(owner()).blocksPerSecond() / 1000000); 
			targetBlock = block.number + (amountToPrint / rewardPerBlock);
            IGovernor(owner()).setInflation(rewardPerBlock);
			
            isRunningGrand = true;
        }
    
    }
    
    /**
     * During the last print of the Grand Fibonaccening
     * It prints up to "double the dose" in order to reach the desired supply
     * Why? to create a big decrease in the price, moving away from everyone's 
     * buy point. It creates a big gap with no overhead resistance, creating the potential for
     * the price to move back up effortlessly
     */
    function startLastPrintGrandFibonaccening() external {
        require(!(IGovernor(owner()).fibonacciDelayed()), "event has been delayed");
        require(grandFibonacceningActivated && !expiredGrandFibonaccening && !isRunningGrand);
		uint256 _totalSupply = IERC20(token).totalSupply();
        require(
             _totalSupply * goldenRatio * goldenRatio / 1000000 >= desiredSupplyAfterGrandFibonaccening,
            "on the last 2 we do it in one, call lastprint"
            );
        
		require(block.timestamp - lastCallFibonaccening > delayBetweenEvents, "pending delay");
        require((block.timestamp % 86400) / 3600 >= 16, "only after 16:00 UTC");
        
        uint256 rewardPerBlock = ( desiredSupplyAfterGrandFibonaccening -  _totalSupply ) / (grandEventLength * IGovernor(owner()).blocksPerSecond() / 1000000); //prints in desired time
		targetBlock = (desiredSupplyAfterGrandFibonaccening -  _totalSupply) / rewardPerBlock;
        IGovernor(owner()).setInflation(rewardPerBlock);
                
        isRunningGrand = true;
        expiredGrandFibonaccening = true;
    }
    function expireLastPrintGrandFibonaccening() external {
        require(isRunningGrand && expiredGrandFibonaccening);
        require(block.number >= (targetBlock-7));
        
		uint256 _totalSupply = IERC20(token).totalSupply();
		uint256 tokensToPrint = (_totalSupply * goldenRatio) / 100000; // 1618 => 1.618 (/1000), 1.618 => 1.618% (/100)
		
        uint256 newEmissions =  tokensToPrint / (365 * 24 * 36 * IGovernor(owner()).blocksPerSecond() / 10000); 
		
        IGovernor(owner()).setInflation(newEmissions);
        isRunningGrand = false;
    }
	
  function setMasterchef() external {
		masterchef = IMasterChef(address(token)).owner();
    }
    
    //transfers ownership of this contract to new governor
    //masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return IDTX(address(token)).governor();
    }
	
	function syncCreditContract() external {
		creditContract = IGovernor(owner()).creditContract();
	}
    
    // this is unneccesary until the Grand Fibonaccening is actually to happen
    // Should perhaps add a proposal to regulate the length and delay
    function updateDelayBetweenEvents(uint256 _delay) external {
        require(msg.sender == owner(), "decentralized voting only");
		delayBetweenEvents = _delay;
    }
    function updateGrandEventLength(uint256 _length) external {
         require(msg.sender == owner(), "decentralized voting only");
    	grandEventLength = _length;
    }

    
    /**
     * After the Fibonaccening event ends, global inflation reduces
     * by -1.618 tokens/block prior to the Grand Fibonaccening and
     * by 1.618 percentile after the Grand Fibonaccening ( * ((100-1.618) / 100))
    */
    function calculateUpcomingRewardPerBlock() public view returns(uint256) {
        if(!expiredGrandFibonaccening) {
            return IGovernor(owner()).lastRegularReward() - goldenRatio * 1e18;
        } else {
            return IGovernor(owner()).lastRegularReward() * 98382 / 100000; 
        }
    }
	
	/**
	 * Can be used for building database from scratch (opposed to using event logs)
	 * also to make sure all data and latest events are synced correctly
	 */
	function proposalLengths() external view returns(uint256, uint256) {
		return(fibonacceningProposals.length, grandFibonacceningProposals.length);
	}
}
