// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IVoting.sol";

//compile with optimization enabled(60runs)
contract DTXbasics {
    address public immutable token; //DTX token (address)
	address private _owner;
	
	address public creditContract;
    
    struct ProposalStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay; //delay is basically time before users can vote against the proposal
        uint256 proposedValue;
    }
    struct RolloverBonusStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        address poolAddress;
        uint256 newBonus;
    }
    struct ParameterStructure {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay; //delay is basically time before users can vote against the proposal
        uint256 proposedValue1; // delay between events
        uint256 proposedValue2; // duration when the print happens
    }
    
    ProposalStructure[] public minDepositProposals;
    ProposalStructure[] public delayProposals;
	ProposalStructure[] public callFeeProposal;
	RolloverBonusStructure[] public rolloverBonuses;
	ProposalStructure[] public minThresholdFibonacceningProposal;
	
	event ProposeMinDeposit(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address enforcer, uint256 delay);
    
    event DelayBeforeEnforce(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address enforcer, uint256 delay);
    
    event InitiateSetCallFee(uint256 proposalID, uint256 depositingTokens, uint256 newCallFee, address enforcer, uint256 delay);
    
    event InitiateRolloverBonus(uint256 proposalID, uint256 depositingTokens, address forPool, uint256 newBonus, address enforcer, uint256 delay);
	
	event ProposeSetMinThresholdFibonaccening(
		uint256 proposalID, 
		uint256 valueSacrificedForVote, 
		uint256 proposedMinDeposit, 
		address indexed enforcer, 
		uint256 delay);

	
	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);

    event ChangeGovernor(address newGovernor);
    
	constructor(address _DTX) {
		token = _DTX;
	}
    
    /**
     * Regulatory process for determining "IGovernor(owner()).IGovernor(owner()).costToVote()()"
     * Anyone should be able to cast a vote
     * Since all votes are deemed valid, unless rejected
     * All votes must be manually reviewed
     * minimum IGovernor(owner()).costToVote() prevents spam
	 * Delay is the time during which you can vote in favor of the proposal(but can't veto/cancle it)
	 * Proposal is submitted. During delay you can vote FOR the proposal. After delay expires the proposal
	 * ... can be cancled(veto'd) if more tokens are commited against than in favor
	 * If not cancled, the proposal can be enforced after (delay + delayBeforeEnforce) expires
	 * ...under condition that more tokens have been sacrificed in favor rather than against
    */
    function initiateSetMinDeposit(uint256 depositingTokens, uint256 newMinDeposit, uint256 delay) external {
		require(newMinDeposit <= IERC20(token).totalSupply() / 10000, 'Maximum 0.01% of all tokens');
		require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	
    	if (newMinDeposit < IGovernor(owner()).costToVote()) {
    		require(depositingTokens >= IGovernor(owner()).costToVote(), "Minimum cost to vote not met");
    		IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	} else {
    		require(depositingTokens >= newMinDeposit, "Must match new amount");
    		IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	}
		
		minDepositProposals.push(
    		        ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newMinDeposit)
    		   ); 
    	
    	emit ProposeMinDeposit(minDepositProposals.length - 1, depositingTokens, newMinDeposit, msg.sender, delay);
    }
	function voteSetMinDepositY(uint256 proposalID, uint256 withTokens) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		minDepositProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteSetMinDepositN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		minDepositProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetMinDeposit(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetMinDeposit(uint256 proposalID) public {
    	require(minDepositProposals[proposalID].valid == true, "Proposal already invalid");
		require(
			minDepositProposals[proposalID].firstCallTimestamp + minDepositProposals[proposalID].delay < block.timestamp, 
			"pending delay"
		);
		require(
			minDepositProposals[proposalID].valueSacrificedForVote < 
			minDepositProposals[proposalID].valueSacrificedAgainst, 
			"needs more votes"
		);

    	minDepositProposals[proposalID].valid = false;  
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }
    function executeSetMinDeposit(uint256 proposalID) public {
    	require(
    	    minDepositProposals[proposalID].valid &&
    	    minDepositProposals[proposalID].firstCallTimestamp + 
			minDepositProposals[proposalID].delay + 
			IGovernor(owner()).delayBeforeEnforce() <= block.timestamp,
    	    "Conditions not met"
    	);
		   
		 if(minDepositProposals[proposalID].valueSacrificedForVote >= minDepositProposals[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).updateCostToVote(minDepositProposals[proposalID].proposedValue); 
			minDepositProposals[proposalID].valid = false;
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
		 } else {
			 vetoSetMinDeposit(proposalID);
		 }
    }

    
    /**
     * Regulatory process for determining "delayBeforeEnforce"
     * After a proposal is initiated, a period of time called
     * delayBeforeEnforce must pass, before the proposal can be enforced
     * During this period proposals can be vetod(voted against = rejected)
    */
    function initiateDelayBeforeEnforceProposal(uint256 depositingTokens, uint256 newDelay, uint256 delay) external { 
    	require(newDelay >= 1 days && newDelay <= 14 days && delay <= IGovernor(owner()).delayBeforeEnforce(), "Minimum 1 day");
    	
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	delayProposals.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newDelay)
    	   );  
		   
        emit DelayBeforeEnforce(delayProposals.length - 1, depositingTokens, newDelay, msg.sender, delay);
    }
	function voteDelayBeforeEnforceProposalY(uint256 proposalID, uint256 withTokens) external {
		require(delayProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		delayProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteDelayBeforeEnforceProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(delayProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		delayProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoDelayBeforeEnforceProposal(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
    function vetoDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(delayProposals[proposalID].valid == true, "Proposal already invalid");
		require(delayProposals[proposalID].firstCallTimestamp + delayProposals[proposalID].delay < block.timestamp, "pending delay");
		require(delayProposals[proposalID].valueSacrificedForVote < delayProposals[proposalID].valueSacrificedAgainst, "needs more votes");
    	
    	delayProposals[proposalID].valid = false;  
		
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    function executeDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(
    	    delayProposals[proposalID].valid == true &&
    	    delayProposals[proposalID].firstCallTimestamp + 
			IGovernor(owner()).delayBeforeEnforce() + 
			delayProposals[proposalID].delay < block.timestamp,
    	    "Conditions not met"
    	);
        
		if(delayProposals[proposalID].valueSacrificedForVote >= delayProposals[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).updateDelayBeforeEnforce(delayProposals[proposalID].proposedValue); 
			delayProposals[proposalID].valid = false;
			
			emit EnforceProposal(1, proposalID, msg.sender, true);
		} else {
			vetoDelayBeforeEnforceProposal(proposalID);
		}
    }

    
  /**
     * Regulatory process for setting rollover bonuses
    */
    function initiateProposalRolloverBonus(uint256 depositingTokens, address _forPoolAddress, uint256 _newBonus, uint256 delay) external { 
		require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "minimum cost to vote");
		require(_newBonus <= 1500, "bonus too high, max 15%");
    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	rolloverBonuses.push(
    	    RolloverBonusStructure(true, block.timestamp, depositingTokens, 0, delay, _forPoolAddress, _newBonus)
    	    );  
    	    
        emit InitiateRolloverBonus(rolloverBonuses.length - 1, depositingTokens, _forPoolAddress, _newBonus, msg.sender, delay);
    }
	function voteProposalRolloverBonusY(uint256 proposalID, uint256 withTokens) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		rolloverBonuses[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(3, proposalID, msg.sender, withTokens, true);
	}
	function voteProposalRolloverBonusN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		rolloverBonuses[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoProposalRolloverBonus(proposalID); }

		emit AddVotes(3, proposalID, msg.sender, withTokens, false);
	}
    function vetoProposalRolloverBonus(uint256 proposalID) public {
    	require(rolloverBonuses[proposalID].valid, "already invalid"); 
		require(rolloverBonuses[proposalID].firstCallTimestamp + rolloverBonuses[proposalID].delay < block.timestamp, "pending delay");
		require(rolloverBonuses[proposalID].valueSacrificedForVote < rolloverBonuses[proposalID].valueSacrificedAgainst, "needs more votes");
 
    	rolloverBonuses[proposalID].valid = false;  
    	
    	emit EnforceProposal(3, proposalID, msg.sender, false);
    }

    function executeProposalRolloverBonus(uint256 proposalID) public {
    	require(
    	    rolloverBonuses[proposalID].valid &&
    	    rolloverBonuses[proposalID].firstCallTimestamp + 
			IGovernor(owner()).delayBeforeEnforce() + 
			rolloverBonuses[proposalID].delay < block.timestamp,
    	    "conditions not met"
    	);
        
		if(rolloverBonuses[proposalID].valueSacrificedForVote >= rolloverBonuses[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).updateRolloverBonus(rolloverBonuses[proposalID].poolAddress, rolloverBonuses[proposalID].newBonus); 
			rolloverBonuses[proposalID].valid = false; 
			
			emit EnforceProposal(3, proposalID, msg.sender, true);
		} else {
			vetoProposalRolloverBonus(proposalID);
		}
    }
    
    
	 /**
     * The auto-compounding effect is achieved with the help of the users that initiate the
     * transaction and pay the gas fee for re-investing earnings into the Masterchef
     * The call fee is paid as a reward to the user
     * This is handled in the auto-compounding contract
     * 
     * This is a process to change the Call fee(the reward) in the autocompounding contracts
     * This contract is an admin for the autocompound contract
     */
    function initiateSetCallFee(uint256 depositingTokens, uint256 newCallFee, uint256 delay) external { 
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "below minimum cost to vote");
    	require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(newCallFee <= 100, "maximum 1%");
    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	callFeeProposal.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newCallFee)
    	   );
    	   
        emit InitiateSetCallFee(callFeeProposal.length - 1, depositingTokens, newCallFee, msg.sender, delay);
    }
	function voteSetCallFeeY(uint256 proposalID, uint256 withTokens) external {
		require(callFeeProposal[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		callFeeProposal[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(4, proposalID, msg.sender, withTokens, true);
	}
	function voteSetCallFeeN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(callFeeProposal[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		callFeeProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetCallFee(proposalID); }

		emit AddVotes(4, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetCallFee(uint256 proposalID) public {
    	require(callFeeProposal[proposalID].valid == true, "Proposal already invalid");
		require(
			callFeeProposal[proposalID].firstCallTimestamp + 
			callFeeProposal[proposalID].delay < block.timestamp, 
			"pending delay"
		);
		require(
			callFeeProposal[proposalID].valueSacrificedForVote < 
			callFeeProposal[proposalID].valueSacrificedAgainst, 
			"needs more votes"
		);

    	callFeeProposal[proposalID].valid = false;
    	
    	emit EnforceProposal(4, proposalID, msg.sender, false);
    }
    function executeSetCallFee(uint256 proposalID) public {
    	require(
    	    callFeeProposal[proposalID].valid && 
    	    callFeeProposal[proposalID].firstCallTimestamp + 
			IGovernor(owner()).delayBeforeEnforce() + 
			callFeeProposal[proposalID].delay < block.timestamp,
    	    "Conditions not met"
    	   );
        
		if(callFeeProposal[proposalID].valueSacrificedForVote >= callFeeProposal[proposalID].valueSacrificedAgainst) {

			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool1(), callFeeProposal[proposalID].proposedValue);
			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool2(), callFeeProposal[proposalID].proposedValue);
			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool3(), callFeeProposal[proposalID].proposedValue);
			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool4(), callFeeProposal[proposalID].proposedValue);
			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool5(), callFeeProposal[proposalID].proposedValue);
			IGovernor(owner()).setCallFee(IGovernor(owner()).acPool6(), callFeeProposal[proposalID].proposedValue);
			
			callFeeProposal[proposalID].valid = false;
			
			emit EnforceProposal(4, proposalID, msg.sender, true);
		} else {
			vetoSetCallFee(proposalID);
		}
    }
	
    /**
     * Regulatory process for determining fibonaccening threshold,
     * which is the minimum amount of tokens required to be collected,
     * before a "fibonaccening" event can be scheduled;
     * 
     * Bitcoin has "halvening" events every 4 years where block rewards reduce in half
     * DTX has "fibonaccening" events, which can can be scheduled once
     * this smart contract collects the minimum(threshold) of tokens. 
     * 
     * Tokens are collected as penalties from premature withdrawals, as well as voting costs inside this contract
     *
     * It's basically a mechanism to re-distribute the penalties(though the rewards can exceed the collected penalties)
     * 
     * It's meant to serve as a volatility-inducing event that attracts new users with high rewards
     * 
     * Effectively, the rewards are increased for a short period of time. 
     * Once the event expires, the tokens collected from penalties are
     * burned to give a sense of deflation AND the global inflation
     * for DTX is reduced by a Golden ratio
    */
    function proposeSetMinThresholdFibonaccening(uint256 depositingTokens, uint256 newMinimum, uint256 delay) external {
        require(newMinimum >= IERC20(token).totalSupply() / 1000, "Min 0.1% of supply");
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
        
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	minThresholdFibonacceningProposal.push(
    	    ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newMinimum)
    	    );
		
    	emit ProposeSetMinThresholdFibonaccening(
    	    minThresholdFibonacceningProposal.length - 1, depositingTokens, newMinimum, msg.sender, delay
    	   );
    }
	function voteSetMinThresholdFibonacceningY(uint256 proposalID, uint256 withTokens) external {
		require(minThresholdFibonacceningProposal[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(5, proposalID, msg.sender, withTokens, true);
	}
	function voteSetMinThresholdFibonacceningN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(minThresholdFibonacceningProposal[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetMinThresholdFibonaccening(proposalID); }

		emit AddVotes(5, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetMinThresholdFibonaccening(uint256 proposalID) public {
    	require(minThresholdFibonacceningProposal[proposalID].valid == true, "Invalid proposal"); 
		require(
			minThresholdFibonacceningProposal[proposalID].firstCallTimestamp + 
			minThresholdFibonacceningProposal[proposalID].delay <= block.timestamp,
			"pending delay"
		);
		require(
			minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote < 
			minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst, 
			"needs more votes"
		);

    	minThresholdFibonacceningProposal[proposalID].valid = false;
    	
    	emit EnforceProposal(5, proposalID, msg.sender, false);
    }
    function executeSetMinThresholdFibonaccening(uint256 proposalID) public {
    	require(
    	    minThresholdFibonacceningProposal[proposalID].valid == true &&
    	    minThresholdFibonacceningProposal[proposalID].firstCallTimestamp + 
			IGovernor(owner()).delayBeforeEnforce() + 
			minThresholdFibonacceningProposal[proposalID].delay < block.timestamp,
    	    "conditions not met"
        );
    	
		if(minThresholdFibonacceningProposal[proposalID].valueSacrificedForVote >= 
			minThresholdFibonacceningProposal[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).setThresholdFibonaccening(minThresholdFibonacceningProposal[proposalID].proposedValue);
			minThresholdFibonacceningProposal[proposalID].valid = false; 
			
			emit EnforceProposal(5, proposalID, msg.sender, true);
		} else {
			vetoSetMinThresholdFibonaccening(proposalID);
		}
    }


    //masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return _owner;
    }

	function syncOwner() external {
		_owner = IDTX(token).governor();
    }
	
	function syncCreditContract() external {
		creditContract = IGovernor(owner()).creditContract();
	}
	
	
	/**
	 * Can be used for building database from scratch (opposed to using event logs)
	 * also to make sure all data and latest events are synced correctly
	 */
	function proposalLengths() external view returns(uint256, uint256, uint256, uint256, uint256) {
		return(
			minDepositProposals.length, 
			delayProposals.length, 
			callFeeProposal.length, 
			rolloverBonuses.length, 
			minThresholdFibonacceningProposal.length
		);
	}
}
