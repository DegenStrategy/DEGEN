// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IVoting.sol";

//compile with optimization enabled(60runs)
contract DTXbasics {
    address public immutable token = ; //DTX token (address)
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
    struct ProposalStructure2 {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay; //delay is basically time before users can vote against the proposal
        address newPool; // New pool to add
    }
    
    ProposalStructure[] public minDepositProposals;
    ProposalStructure[] public delayProposals;
	RolloverBonusStructure[] public rolloverBonuses;
	ProposalStructure2[] public newPoolProposal;
	
	uint256 newPoolThresholdMultiplier = 250;
	
	event ProposeMinDeposit(uint256 indexed proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address indexed enforcer, uint256 delay);
    
    event DelayBeforeEnforce(uint256 indexed proposalID, uint256 valueSacrificedForVote, uint256 proposedMinDeposit, address indexed enforcer, uint256 delay);
    
    event InitiateSetCallFee(uint256 indexed proposalID, uint256 depositingTokens, uint256 newCallFee, address indexed enforcer, uint256 delay);
    
    event InitiateRolloverBonus(uint256 indexed proposalID, uint256 depositingTokens, address indexed forPool, uint256 newBonus, address indexed enforcer, uint256 delay);
	
	event ProposeNewPool(uint256 indexed proposalID, uint256 valueSacrificedForVote, address newPool, address indexed enforcer, uint256 delay);
	
	event ProposeSetMinThresholdFibonaccening(
		uint256 proposalID, 
		uint256 valueSacrificedForVote, 
		uint256 proposedMinDeposit, 
		address indexed enforcer, 
		uint256 delay);

	
	event AddVotes(uint256 _type, uint256 indexed proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 indexed proposalID, address indexed enforcer, bool isSuccess);


    
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
    	} else {
    		require(depositingTokens >= newMinDeposit, "Must match new amount");
    	}

		IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
		
		minDepositProposals.push(
    		        ProposalStructure(true, block.timestamp, depositingTokens, 0, delay, newMinDeposit)
    		   ); 
    	
    	emit ProposeMinDeposit(minDepositProposals.length - 1, depositingTokens, newMinDeposit, msg.sender, delay);
    }
	function voteSetMinDepositY(uint256 proposalID, uint256 withTokens) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		require(
			(	minDepositProposals[proposalID].firstCallTimestamp 
				+ minDepositProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		minDepositProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteSetMinDepositN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(minDepositProposals[proposalID].valid, "invalid");
		require(
			(	minDepositProposals[proposalID].firstCallTimestamp 
				+ minDepositProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		minDepositProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoSetMinDeposit(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoSetMinDeposit(uint256 proposalID) public {
    	require(minDepositProposals[proposalID].valid, "Proposal already invalid");
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
			IGovernor(owner()).delayBeforeEnforce() < block.timestamp,
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
	
	function initiateNewPool(uint256 depositingTokens, address _newPool, uint256 delay) external {
		require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(depositingTokens >= IGovernor(owner()).costToVote()*newPoolThresholdMultiplier, "Below minimum threshold");

		IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
		
		newPoolProposal.push(
    		        ProposalStructure2(true, block.timestamp, depositingTokens, 0, delay, _newPool)
    		   ); 
    	
    	emit ProposeNewPool(newPoolProposal.length - 1, depositingTokens, _newPool, msg.sender, delay);
    }
	function voteNewPoolY(uint256 proposalID, uint256 withTokens) external {
		require(newPoolProposal[proposalID].valid, "invalid");
		require(
			(	newPoolProposal[proposalID].firstCallTimestamp 
				+ newPoolProposal[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		newPoolProposal[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(2, proposalID, msg.sender, withTokens, true);
	}
	function voteNewPoolN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(newPoolProposal[proposalID].valid, "invalid");
		require(
			(	newPoolProposal[proposalID].firstCallTimestamp 
				+ newPoolProposal[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		newPoolProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoNewPool(proposalID); }

		emit AddVotes(2, proposalID, msg.sender, withTokens, false);
	}
    function vetoNewPool(uint256 proposalID) public {
    	require(newPoolProposal[proposalID].valid, "Proposal already invalid");
		require(
			newPoolProposal[proposalID].firstCallTimestamp + newPoolProposal[proposalID].delay < block.timestamp, 
			"pending delay"
		);
		require(
			newPoolProposal[proposalID].valueSacrificedForVote < 
			newPoolProposal[proposalID].valueSacrificedAgainst, 
			"needs more votes"
		);

    	newPoolProposal[proposalID].valid = false;  
    	
    	emit EnforceProposal(2, proposalID, msg.sender, false);
    }
    function executeNewPool(uint256 proposalID) public {
    	require(
    	    newPoolProposal[proposalID].valid &&
    	    newPoolProposal[proposalID].firstCallTimestamp + 
			newPoolProposal[proposalID].delay + 
			IGovernor(owner()).delayBeforeEnforce() < block.timestamp,
    	    "Conditions not met"
    	);
		   
		 if(newPoolProposal[proposalID].valueSacrificedForVote >= newPoolProposal[proposalID].valueSacrificedAgainst &&
				newPoolProposal[proposalID].valueSacrificedForVote >= IGovernor(owner()).costToVote() * newPoolThresholdMultiplier) {
			IGovernor(owner()).addNewPool(newPoolProposal[proposalID].newPool); 
			newPoolProposal[proposalID].valid = false;
			
			emit EnforceProposal(2, proposalID, msg.sender, true);
		 } else {
			 vetoNewPool(proposalID);
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
		require(
			(	delayProposals[proposalID].firstCallTimestamp 
				+ delayProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		delayProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(1, proposalID, msg.sender, withTokens, true);
	}
	function voteDelayBeforeEnforceProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(delayProposals[proposalID].valid, "invalid");
		require(
			(	delayProposals[proposalID].firstCallTimestamp 
				+ delayProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		delayProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoDelayBeforeEnforceProposal(proposalID); }

		emit AddVotes(1, proposalID, msg.sender, withTokens, false);
	}
    function vetoDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(delayProposals[proposalID].valid, "Proposal already invalid");
		require(delayProposals[proposalID].firstCallTimestamp + delayProposals[proposalID].delay < block.timestamp, "pending delay");
		require(delayProposals[proposalID].valueSacrificedForVote < delayProposals[proposalID].valueSacrificedAgainst, "needs more votes");
    	
    	delayProposals[proposalID].valid = false;  
		
    	emit EnforceProposal(1, proposalID, msg.sender, false);
    }
    function executeDelayBeforeEnforceProposal(uint256 proposalID) public {
    	require(
    	    delayProposals[proposalID].valid &&
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
		require(_newBonus <= 1000, "bonus too high, max 10%");
    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	rolloverBonuses.push(
    	    RolloverBonusStructure(true, block.timestamp, depositingTokens, 0, delay, _forPoolAddress, _newBonus)
    	    );  
    	    
        emit InitiateRolloverBonus(rolloverBonuses.length - 1, depositingTokens, _forPoolAddress, _newBonus, msg.sender, delay);
    }
	function voteProposalRolloverBonusY(uint256 proposalID, uint256 withTokens) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		require(
			(	rolloverBonuses[proposalID].firstCallTimestamp 
				+ rolloverBonuses[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		rolloverBonuses[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(3, proposalID, msg.sender, withTokens, true);
	}
	function voteProposalRolloverBonusN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(rolloverBonuses[proposalID].valid, "invalid");
		require(
			(	rolloverBonuses[proposalID].firstCallTimestamp 
				+ rolloverBonuses[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
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
    

	
	function updateNewPoolProposalThreshold(uint256 _amount) external {
		require(msg.sender == owner(), "Only through decentralized voting!");
		newPoolThresholdMultiplier = _amount;
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
	function proposalLengths() external view returns(uint256, uint256, uint256, uint256) {
		return(
			minDepositProposals.length, 
			newPoolProposal.length,
			delayProposals.length, 
			rolloverBonuses.length
		);
	}

	//masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return _owner;
    }
}
