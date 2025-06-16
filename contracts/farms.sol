// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IGovernor.sol";
import "./interface/IMasterChef.sol";
import "./interface/IDTX.sol";
import "./interface/IVoting.sol";


//contract that regulates the farms for DTX
contract DTXfarms {
	struct ProposalFarm {
        bool valid;
        uint256 poolid;
        uint256 newAllocation;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
        uint256 firstCallTimestamp;
        uint16 newDepositFee;
    }

	//we no longer have govTransfer
	// burn sets transfer tax, non-burn sets percentageAllocatedToPulseEcosystem
     struct ProposalGovTransfer {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
		bool isBurn; //if "burn" - > is to set transfer tax
		uint256 startTimestamp; //can schedule in advance when they are burned
    }
	
   struct ProposalTax {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
    }
	
	struct ProposalVault {	
        bool valid;	
        uint256 firstCallTimestamp;	
        uint256 proposedType;	
        uint256 proposedValue;	
		uint256 valueSacrificedForVote;	
		uint256 valueSacrificedAgainst;	
		uint256 delay;	
    }

    ProposalFarm[] public proposalFarmUpdate;
	ProposalGovTransfer[] public governorTransferProposals; 
	ProposalTax[] public govTaxProposals; 
	ProposalVault[] public vaultProposals;
	
	mapping(uint256 => uint256) public poolAllocationPercentage; 
	uint256 public percentageAllocatedToPulseEcosystem;
    
    address public immutable token = ; //DTX token(address!)
	address private _owner;
	
	address public creditContract;
	
	address public masterchef = ;
	

    
    event InitiateFarmProposal(
            uint256 indexed proposalID, uint256 depositingTokens, uint256 indexed poolid,
            uint256 newAllocation, uint16 depositFee, address indexed enforcer, uint256 delay
        );
    
    event ProposeGovernorTransfer(uint256 indexed proposalID, uint256 valueSacrificedForVote, uint256 proposedAmount, address indexed enforcer, bool isBurn, uint256 startTimestamp, uint256 delay);

	event ProposeGovTax(uint256 indexed proposalID, uint256 valueSacrificedForVote, uint256 proposedTax, address indexed enforcer, uint256 delay);

    event ProposeVault(uint256 indexed proposalID, uint256 valueSacrificedForVote, uint256 indexed _type, uint256 _amount, address indexed enforcer, uint256 delay);

	event AddVotes(uint256 indexed _type, uint256 indexed proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 indexed _type, uint256 indexed proposalID, address indexed enforcer, bool isSuccess);

	
	function rebalancePools() public {
		uint256 _totalAllocatedToXPDMiners; //allocation points here
		for(uint i = 0; i <= 3; ++i) {
			(uint256 _allocation, , ) = IMasterChef(masterchef).poolInfo(i);
			_totalAllocatedToXPDMiners+= _allocation;
		}

		uint256 _poolLength = IMasterChef(masterchef).poolLength();

		uint256 _percentageAllocatedToXPDMiners = 10000 - percentageAllocatedToPulseEcosystem;
		uint256 _multiplier = 100000000 / _percentageAllocatedToXPDMiners;
		uint256 _newTotalAllocation = (_totalAllocatedToXPDMiners * _multiplier) / 10000;

		IMasterChef(masterchef).massUpdatePools();
		for(uint i=4; i < _poolLength; ++i) {
			uint256 _newAlloc = _newTotalAllocation * poolAllocationPercentage[i] / 10000;
			IGovernor(owner()).setPool(i, _newAlloc, false);
		}
	}
    
    /**
     * Regulatory process to regulate rewards for PulseChain Ecosystem
     * depositFee is unused (has been left because it would require to change front ends, event listeners and what not....)
    */    
    function initiateFarmProposal(
            uint256 depositingTokens, uint256 poolid, uint256 newAllocation, uint16 depositFee, uint256 delay
        ) external { 
    	require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "there is a minimum cost to vote");
    	require(poolid > 3 && poolid < IMasterChef(masterchef).poolLength(), "only allowed for these pools"); 
		

    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens); 
    	proposalFarmUpdate.push(
    	    ProposalFarm(true, poolid, newAllocation, depositingTokens, 0, delay, block.timestamp, 0)
    	    ); 
    	emit InitiateFarmProposal(proposalFarmUpdate.length - 1, depositingTokens, poolid, newAllocation, 0, msg.sender, delay);
    }
	function voteFarmProposalY(uint256 proposalID, uint256 withTokens) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		require(
			(	proposalFarmUpdate[proposalID].firstCallTimestamp 
				+ proposalFarmUpdate[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		proposalFarmUpdate[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteFarmProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		require(
			(	proposalFarmUpdate[proposalID].firstCallTimestamp 
				+ proposalFarmUpdate[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		proposalFarmUpdate[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoFarmProposal(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoFarmProposal(uint256 proposalID) public {
    	require(proposalFarmUpdate[proposalID].valid, "already invalid");
		require(proposalFarmUpdate[proposalID].firstCallTimestamp + proposalFarmUpdate[proposalID].delay <= block.timestamp, "pending delay");
		require(proposalFarmUpdate[proposalID].valueSacrificedForVote < proposalFarmUpdate[proposalID].valueSacrificedAgainst, "needs more votes");
    	proposalFarmUpdate[proposalID].valid = false; 
    	
    	emit EnforceProposal(0, proposalID, msg.sender, false);
    }
    
    /**
     * Updates the rewards for the corresponding farm in the proposal
    */
    function updateFarm(uint256 proposalID, bool _withUpdate) public {
        require(proposalFarmUpdate[proposalID].valid, "invalid proposal");
        require(
            proposalFarmUpdate[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + proposalFarmUpdate[proposalID].delay  < block.timestamp,
            "delay before enforce not met"
            );
        
		if(proposalFarmUpdate[proposalID].valueSacrificedForVote >= proposalFarmUpdate[proposalID].valueSacrificedAgainst) {
			uint256 _poolID = proposalFarmUpdate[proposalID].poolid;
			uint256 _newAllocation = proposalFarmUpdate[proposalID].newAllocation;
			uint256 _newTotalToPulse = percentageAllocatedToPulseEcosystem - poolAllocationPercentage[_poolID] + _newAllocation;

			percentageAllocatedToPulseEcosystem = _newTotalToPulse;
			poolAllocationPercentage[_poolID] = _newAllocation;
			proposalFarmUpdate[proposalID].valid = false;
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
			
			if(_withUpdate) {
				rebalancePools();
			}
		} else {
			vetoFarmProposal(proposalID);
		}
    }


	/*
	* Transfer tokens from governor into treasury wallet OR burn them from governor
	* alternatively could change devaddr to the treasury wallet in masterchef(portion of inflation goes to devaddr)
	*/
  function proposeGovernorTransfer(uint256 depositingTokens, uint256 _amount, bool _isBurn, uint256 _timestamp, uint256 delay) external {
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		if(!_isBurn) {
			require(_amount > 0 && _amount <= 10000, "out of bounds");
		} else {
			require(depositingTokens >= 1000 * IGovernor(owner()).costToVote(), "1000 * minimum cost to vote required");
		}
        
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	governorTransferProposals.push(
    	    ProposalGovTransfer(true, block.timestamp, _amount, depositingTokens, 0, delay, _isBurn, _timestamp)
    	    );
		
    	emit ProposeGovernorTransfer(
    	    governorTransferProposals.length - 1, depositingTokens, _amount, msg.sender, _isBurn, _timestamp, delay
    	   );
    }
	function voteGovernorTransferY(uint256 proposalID, uint256 withTokens) external {
		require(governorTransferProposals[proposalID].valid, "invalid");
		require(
			(	governorTransferProposals[proposalID].firstCallTimestamp 
				+ governorTransferProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		governorTransferProposals[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(2, proposalID, msg.sender, withTokens, true);
	}
	function voteGovernorTransferN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(governorTransferProposals[proposalID].valid, "invalid");
		require(
			(	governorTransferProposals[proposalID].firstCallTimestamp 
				+ governorTransferProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		governorTransferProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovernorTransfer(proposalID); }

		emit AddVotes(2, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovernorTransfer(uint256 proposalID) public {
    	require(governorTransferProposals[proposalID].valid, "Invalid proposal"); 
		require(governorTransferProposals[proposalID].firstCallTimestamp + governorTransferProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(governorTransferProposals[proposalID].valueSacrificedForVote < governorTransferProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	governorTransferProposals[proposalID].valid = false;

		emit EnforceProposal(2, proposalID, msg.sender, false);
    }
    function executeGovernorTransfer(uint256 proposalID) public {
    	require(
    	    governorTransferProposals[proposalID].valid &&
    	    governorTransferProposals[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + governorTransferProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		require(governorTransferProposals[proposalID].startTimestamp < block.timestamp, "Not yet eligible");
    	
		if(governorTransferProposals[proposalID].valueSacrificedForVote >= governorTransferProposals[proposalID].valueSacrificedAgainst) {
			if(governorTransferProposals[proposalID].isBurn) {
				IGovernor(owner()).burnTokens(governorTransferProposals[proposalID].proposedValue);
			} else {
				percentageAllocatedToPulseEcosystem = governorTransferProposals[proposalID].proposedValue;
			}

			governorTransferProposals[proposalID].valid = false; 
			
			emit EnforceProposal(2, proposalID, msg.sender, true);
		} else {
			vetoGovernorTransfer(proposalID);
		}
    }
	
	//in case masterchef is changed
   function setMasterchef() external {
        masterchef = IDTX(token).owner();
    }

	function syncOwner() external {
		_owner = IDTX(token).governor();
    }
	
	//Proposals to set governor 'tax'(in masterchef, on every mint a % of inflation goes to the governor)
  function proposeGovTax(uint256 depositingTokens, uint256 _amount, uint256 delay) external {
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(_amount <= 1000, "max 1000");
        
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
    	govTaxProposals.push(
    	    ProposalTax(true, block.timestamp, _amount, depositingTokens, 0, delay)
    	    );
		
    	emit ProposeGovTax(
    	    govTaxProposals.length - 1, depositingTokens, _amount, msg.sender, delay
    	   );
    }
	function voteGovTaxY(uint256 proposalID, uint256 withTokens) external {
		require(govTaxProposals[proposalID].valid, "invalid");
		require(
			(	govTaxProposals[proposalID].firstCallTimestamp 
				+ govTaxProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		govTaxProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(4, proposalID, msg.sender, withTokens, true);
	}
	function voteGovTaxN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(govTaxProposals[proposalID].valid, "invalid");
		require(
			(	govTaxProposals[proposalID].firstCallTimestamp 
				+ govTaxProposals[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		govTaxProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovTax(proposalID); }

		emit AddVotes(4, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovTax(uint256 proposalID) public {
    	require(govTaxProposals[proposalID].valid, "Invalid proposal");
		require(govTaxProposals[proposalID].firstCallTimestamp + govTaxProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(govTaxProposals[proposalID].valueSacrificedForVote < govTaxProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	govTaxProposals[proposalID].valid = false;
    	
    	emit EnforceProposal(4, proposalID, msg.sender, false);
    }
    function executeGovTax(uint256 proposalID) public {
    	require(
    	    govTaxProposals[proposalID].valid &&
    	    govTaxProposals[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + govTaxProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		
		if(govTaxProposals[proposalID].valueSacrificedForVote >= govTaxProposals[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).setGovernorTax(govTaxProposals[proposalID].proposedValue);
			govTaxProposals[proposalID].valid = false; 
			
			emit EnforceProposal(4, proposalID, msg.sender, true);
		} else {
			vetoGovTax(proposalID);
		}
    }
	
		    //process for setting deposit fee, funding fee and referral reward	
    function proposeVault(uint256 depositingTokens, uint256 _type, uint256 _amount, uint256 delay) external {	
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");	
        require(delay <= 7 days, "must be shorter than 7 days");	
        //  Vault has requirement for maximum amount	
        	
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);	
    	vaultProposals.push(	
    	    ProposalVault(true, block.timestamp, _type, _amount, depositingTokens, 0, delay)	
    	    );	
    	emit ProposeVault(	
    	    vaultProposals.length - 1, depositingTokens, _type, _amount, msg.sender, delay	
    	   );	
    }	
	function voteVaultY(uint256 proposalID, uint256 withTokens) external {	
		require(vaultProposals[proposalID].valid, "invalid");	
		require(
			(	vaultProposals[proposalID].firstCallTimestamp 
				+ vaultProposals[proposalID].delay 
				+ 7 days
			) 
				> block.timestamp,
			"can already be enforced"
		);
			
		IVoting(creditContract).deductCredit(msg.sender, withTokens);	
		vaultProposals[proposalID].valueSacrificedForVote+= withTokens;	
				
		emit AddVotes(5, proposalID, msg.sender, withTokens, true);	
	}	
	function voteVaultN(uint256 proposalID, uint256 withTokens, bool withAction) external {	
		require(vaultProposals[proposalID].valid, "invalid");	
		require(
			(	vaultProposals[proposalID].firstCallTimestamp 
				+ vaultProposals[proposalID].delay 
				+ 7 days
			) 
				> block.timestamp,
			"can already be enforced"
		);
			
		IVoting(creditContract).deductCredit(msg.sender, withTokens);	
			
		vaultProposals[proposalID].valueSacrificedAgainst+= withTokens;	
		if(withAction) { vetoVault(proposalID); }	
		emit AddVotes(5, proposalID, msg.sender, withTokens, false);	
	}	
    function vetoVault(uint256 proposalID) public {	
    	require(vaultProposals[proposalID].valid, "Invalid proposal"); 	
		require(vaultProposals[proposalID].firstCallTimestamp + vaultProposals[proposalID].delay <= block.timestamp, "pending delay");	
		require(vaultProposals[proposalID].valueSacrificedForVote < vaultProposals[proposalID].valueSacrificedAgainst, "needs more votes");	
			
    	vaultProposals[proposalID].valid = false;	
		emit EnforceProposal(5, proposalID, msg.sender, false);	
    }	
    function executeVault(uint256 proposalID) public {	
    	require(	
    	    vaultProposals[proposalID].valid &&	
    	    vaultProposals[proposalID].firstCallTimestamp + 7 days + vaultProposals[proposalID].delay  < block.timestamp,	
    	    "conditions not met"	
        );	
    		
		if(vaultProposals[proposalID].valueSacrificedForVote >= vaultProposals[proposalID].valueSacrificedAgainst) {	
            IGovernor(owner()).updateVault(vaultProposals[proposalID].proposedType, vaultProposals[proposalID].proposedValue);	
			vaultProposals[proposalID].valid = false; 	
				
			emit EnforceProposal(5, proposalID, msg.sender, true);	
		} else {	
			vetoVault(proposalID);	
		}	
    }


    function syncCreditContract() external {
		creditContract = IGovernor(owner()).creditContract();
	}
	
	/**
	 * Can be used for building database from scratch (opposed to using event logs)
	 * also to make sure all data and latest events are synced correctly
	 */
	function proposalLengths() external view returns(uint256, uint256, uint256, uint256) {
		return(proposalFarmUpdate.length, vaultProposals.length, governorTransferProposals.length, govTaxProposals.length);
	}

	//masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return _owner;
    }
}
