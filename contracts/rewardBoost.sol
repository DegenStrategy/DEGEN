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
    
    FibonacceningProposal[] public fibonacceningProposals;

    //WARNING: careful where we are using 1e18 and where not
    uint256 public immutable goldenRatio = 1618; //1.618 is the golden ratio
    IERC20 public immutable token; //DTX token
	
    
    //masterchef address
    address public masterchef;
	
	address public creditContract;
    
    uint256 public lastCallFibonaccening; //stores timestamp of last grand fibonaccening event
    
    uint256 public targetBlock; // used for calculating target block

    uint256 public fibonacceningActiveID;
    uint256 public fibonacceningActivatedBlock;
    
    uint256 public tokensForBurn; //tokens we draw from governor to burn for fib event
	
	bool public expiredGrandFibonaccening;


    event ProposeFibonaccening(uint256 proposalID, uint256 valueSacrificedForVote, uint256 startTime, uint256 durationInBlocks, uint256 newRewardPerBlock , address indexed enforcer, uint256 delay);

    event EndFibonaccening(uint256 proposalID, address indexed enforcer);
    event CancleFibonaccening(uint256 proposalID, address indexed enforcer);
    
    event RebalanceInflation(uint256 newRewardPerBlock);
    
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);
    
    event ChangeGovernor(address newGovernor);
	
	constructor (IERC20 _DTX, address _masterchef) {
		token = _DTX;
		masterchef = _masterchef;
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
            startTimestamp - block.timestamp <= 90 days, "max 90 days"); 
		require(
			(newRewardPerBlock * durationInBlocks) < (IDTX(token).totalPublished() * 5 / 100),
			"Safeguard: Can't print more than 5% of tokens in single event"
		);

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
        require(
            IERC20(token).balanceOf(owner()) >= IGovernor(owner()).thresholdFibonaccening(),
            "needa collect penalties");
    	require(fibonacceningProposals[proposalID].valid == true, "invalid proposal");
    	require(block.timestamp >= fibonacceningProposals[proposalID].startTime, "can only start when set");
    	require(!(IGovernor(owner()).eventFibonacceningActive()), "already active");
    	
    	if(fibonacceningProposals[proposalID].valueSacrificedForVote >= fibonacceningProposals[proposalID].valueSacrificedAgainst) {
			tokensForBurn = IGovernor(owner()).thresholdFibonaccening();
			IGovernor(owner()).transferRewardBoostThreshold();
			
			IGovernor(owner()).rememberReward(); // remembers last regular rewar(before boost)
			IGovernor(owner()).setInflation(fibonacceningProposals[proposalID].rewardPerBlock);
			
			fibonacceningProposals[proposalID].valid = false;
			fibonacceningActiveID = proposalID;
			fibonacceningActivatedBlock = block.number;
			IGovernor(owner()).setActivateFibonaccening(true);
			
			if(IMasterChef(masterchef).DTXPerBlock() <= 1618 * 1e15) {
				expiredGrandFibonaccening = true;
			}
			
			
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
		require(fibonacceningActivatedBlock > 0, "invalid"); // on contract launch activatedBlock = 0;
        require(
            block.number >= fibonacceningActivatedBlock + fibonacceningProposals[fibonacceningActiveID].duration, 
            "not yet expired"
           ); 
        
        uint256 newAmount = calculateUpcomingRewardPerBlock();
        
        IGovernor(owner()).setInflation(newAmount);
        IGovernor(owner()).setActivateFibonaccening(false);
        
    	IDTX(address(token)).burn(tokensForBurn); // burns the tokens - "fibonaccening" sacrifice
		
		if(expiredGrandFibonaccening) {
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

    
    /**
     * After the Reward Boost event ends, global inflation reduces
     * by -1.618 tokens 
     * ... Or to 1.618% on annual basis (on underflow)
    */
    function calculateUpcomingRewardPerBlock() public view returns(uint256) {
		if(!expiredGrandFibonaccening) {
			return IGovernor(owner()).lastRegularReward() - 1618 * 1e15; // Reduce reward by 1.618 reward per block
		} else {
			uint256 _factor = 1618 * 1e15;
			for(uint256 i = 0; i < IGovernor(owner()).totalFibonacciEventsAfterGrand(); i++) {
				_factor = _factor * 98382 / 100000; //factor is multiplied * 1000 (number is 1618, when actual factor is 1.618)
			}
			
			uint256 _initialSupply = IDTX(token).totalPublished();
			
			uint256 supplyToPrint = _initialSupply * _factor / 100000; 
		
			uint256 rewardPerBlock = supplyToPrint / (365 * 24 * 36 * IGovernor(owner()).blocksPerSecond() / 10000);
		}
    }
	
	
	/**
	 * Can be used for building database from scratch (opposed to using event logs)
	 * also to make sure all data and latest events are synced correctly
	 */
	function proposalLengths() external view returns(uint256) {
		return(fibonacceningProposals.length);
	}
}
