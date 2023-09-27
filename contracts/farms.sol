// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";

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

     struct ProposalGovTransfer {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 proposedValue;
		uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
		bool isBurn; //if burn, burns tokens. Else transfers into treasury
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
	
	mapping(uint256 => uint256) public poolAllocation;
    
    address public immutable token; //DTX token(address!)
	address private _owner;
	
	address public creditContract;
	
	address public masterchef;
    
	uint256 public maxNftAllocation = 1500;
	
	uint256 public maxPulseEcoAllocation = 6000; //max 60% per pool
	uint256 public maxPulseEcoTotalAllocation = 9000; // max 90% total (at beginning)
	uint256 public lastReducePulseAllocation; //block timestamp when maximum pulse ecosystem allocation is reduced
    
    event InitiateFarmProposal(
            uint256 proposalID, uint256 depositingTokens, uint256 poolid,
            uint256 newAllocation, uint16 depositFee, address indexed enforcer, uint256 delay
        );
    
    //reward reduction for farms and meme pools during reward boosts
    event ProposeRewardReduction(address enforcer, uint256 proposalID, uint256 farmMultiplier, uint256 memeMultiplier, uint256 depositingTokens, uint256 delay);
	
    event ProposeGovernorTransfer(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedAmount, address indexed enforcer, bool isBurn, uint256 startTimestamp, uint256 delay);

	event ProposeGovTax(uint256 proposalID, uint256 valueSacrificedForVote, uint256 proposedTax, address indexed enforcer, uint256 delay);

    event ProposeVault(uint256 proposalID, uint256 valueSacrificedForVote, uint256 _type, uint256 _amount, address indexed enforcer, uint256 delay);

	event AddVotes(uint256 _type, uint256 proposalID, address indexed voter, uint256 tokensSacrificed, bool _for);
	event EnforceProposal(uint256 _type, uint256 proposalID, address indexed enforcer, bool isSuccess);
    
	constructor (address _DTX, address _masterchef, uint256 _launch)  {
		token = _DTX;
		masterchef = _masterchef;
		lastReducePulseAllocation = _launch + 7 days;
		poolAllocation[10] = 9000; // Begin with allocation to Hex miners(T-shares)
	}

	//ability to change max allocations without launching new contract
	function changeMaxAllocations(uint256 _lp, uint256 _nft, uint256 _maxPulse, uint256 _maxPulseTotal) external {
        require(msg.sender == owner(), "owner only");
		maxNftAllocation = _nft;
        maxPulseEcoAllocation = _maxPulse;
        maxPulseEcoTotalAllocation = _maxPulseTotal;
	}
	
	function rebalancePools() public {
		uint256 _totalAllocatedToXPDMiners; //allocation points here
		for(uint i = 0; i <= 5; i++) {
			(uint256 _allocation, , ) = IMasterChef(masterchef).poolInfo(i);
			_totalAllocatedToXPDMiners+= _allocation;
		}

		uint256 _percentageAllocatedToPulseEcosystem = 0; //Percentages here
		for(uint i=6; i <= 11; i++) {
			_percentageAllocatedToPulseEcosystem+= poolAllocation[i];
		}

		uint256 _percentageAllocatedToXPDMiners = 10000 - _percentageAllocatedToPulseEcosystem;
		uint256 _multiplier = 100000000 / _percentageAllocatedToXPDMiners;
		uint256 _newTotalAllocation = (_totalAllocatedToXPDMiners * _multiplier) / 10000;

		for(uint i=6; i <= 11; i++) {
			uint256 _newAlloc = _newTotalAllocation * poolAllocation[i] / 10000;
			IGovernor(owner()).setPool(i, _newAlloc, 0, false);
		}
		IMasterChef(masterchef).massUpdatePools();
	}
    
    /**
     * Regulatory process to regulate rewards for PulseChain Ecosystem
    */    
    function initiateFarmProposal(
            uint256 depositingTokens, uint256 poolid, uint256 newAllocation, uint16 depositFee, uint256 delay
        ) external { 
    	require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "there is a minimum cost to vote");
    	require(poolid > 5 && poolid <= 11, "only allowed for these pools"); 
		
		//6,7,8,9,10 are  PLS,PLSX,HEX,INC,T-Share
		//11 is for NFT mining
    	if(poolid == 11) {
			require(
    	        newAllocation <= maxNftAllocation,
    	        "exceeds max allocation"
    	       );
		} else {
    	    require(
    	        newAllocation <= maxPulseEcoAllocation,
    	        "exceeds max allocation"
    	       ); 
    	}
    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens); 
    	proposalFarmUpdate.push(
    	    ProposalFarm(true, poolid, newAllocation, depositingTokens, 0, delay, block.timestamp, 0)
    	    ); 
    	emit InitiateFarmProposal(proposalFarmUpdate.length - 1, depositingTokens, poolid, newAllocation, 0, msg.sender, delay);
    }
	function voteFarmProposalY(uint256 proposalID, uint256 withTokens) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		proposalFarmUpdate[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteFarmProposalN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(proposalFarmUpdate[proposalID].valid, "invalid");
		
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
		uint256 _poolID = proposalFarmUpdate[proposalID].poolid;
		uint256 _pulseEcoCount = 0;
		uint256 _newAllocation = proposalFarmUpdate[proposalID].newAllocation;
        
		if(proposalFarmUpdate[proposalID].valueSacrificedForVote >= proposalFarmUpdate[proposalID].valueSacrificedAgainst) {

			//check so it does not exceed total
			for(uint256 i= 6; i<=11; i++) {
				if(_poolID != i) { 
					_pulseEcoCount+= poolAllocation[i];
				} else {
					_pulseEcoCount+= _newAllocation;
				}
			}
			require(_pulseEcoCount <= maxPulseEcoTotalAllocation, "exceeds maximum allowed allocation for pulse ecosystem");

			poolAllocation[_poolID] = _newAllocation;
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
		require(_amount <= IERC20(token).balanceOf(owner()), "insufficient balance");
        
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
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		governorTransferProposals[proposalID].valueSacrificedForVote+= withTokens;
			
		emit AddVotes(2, proposalID, msg.sender, withTokens, true);
	}
	function voteGovernorTransferN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(governorTransferProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		governorTransferProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovernorTransfer(proposalID); }

		emit AddVotes(2, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovernorTransfer(uint256 proposalID) public {
    	require(governorTransferProposals[proposalID].valid == true, "Invalid proposal"); 
		require(governorTransferProposals[proposalID].firstCallTimestamp + governorTransferProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(governorTransferProposals[proposalID].valueSacrificedForVote < governorTransferProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	governorTransferProposals[proposalID].valid = false;

		emit EnforceProposal(2, proposalID, msg.sender, false);
    }
    function executeGovernorTransfer(uint256 proposalID) public {
    	require(
    	    governorTransferProposals[proposalID].valid == true &&
    	    governorTransferProposals[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + governorTransferProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		require(governorTransferProposals[proposalID].startTimestamp < block.timestamp, "Not yet eligible");
    	
		if(governorTransferProposals[proposalID].valueSacrificedForVote >= governorTransferProposals[proposalID].valueSacrificedAgainst) {
			if(governorTransferProposals[proposalID].isBurn) {
				if(IDTX(token).balanceOf(owner()) >= governorTransferProposals[proposalID].proposedValue) {
					IGovernor(owner()).burnTokens(governorTransferProposals[proposalID].proposedValue);
				}
			} else {
				IGovernor(owner()).transferToTreasury(governorTransferProposals[proposalID].proposedValue);
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
	
	//Proposals to set governor 'tax'(in masterchef, on every mint this % of inflation goes to the governor)
	//1000 = 10%. Max 10%
	// ( mintTokens * thisAmount / 10 000 ) in the masterchef contract
  function proposeGovTax(uint256 depositingTokens, uint256 _amount, uint256 delay) external {
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
		require(_amount <= 1000 && _amount > 0, "max 1000");
        
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
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		govTaxProposals[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(4, proposalID, msg.sender, withTokens, true);
	}
	function voteGovTaxN(uint256 proposalID, uint256 withTokens, bool withAction) external {
		require(govTaxProposals[proposalID].valid, "invalid");
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		govTaxProposals[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoGovTax(proposalID); }

		emit AddVotes(4, proposalID, msg.sender, withTokens, false);
	}
    function vetoGovTax(uint256 proposalID) public {
    	require(govTaxProposals[proposalID].valid == true, "Invalid proposal");
		require(govTaxProposals[proposalID].firstCallTimestamp + govTaxProposals[proposalID].delay <= block.timestamp, "pending delay");
		require(govTaxProposals[proposalID].valueSacrificedForVote < govTaxProposals[proposalID].valueSacrificedAgainst, "needs more votes");
		
    	govTaxProposals[proposalID].valid = false;
    	
    	emit EnforceProposal(4, proposalID, msg.sender, false);
    }
    function executeGovTax(uint256 proposalID) public {
    	require(
    	    govTaxProposals[proposalID].valid == true &&
    	    govTaxProposals[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + govTaxProposals[proposalID].delay  < block.timestamp,
    	    "conditions not met"
        );
		
		if(govTaxProposals[proposalID].valueSacrificedForVote >= govTaxProposals[proposalID].valueSacrificedAgainst) {
			IGovernor(owner()).setGovernorTax(govTaxProposals[proposalID].proposedValue); //burns the tokens
			govTaxProposals[proposalID].valid = false; 
			
			emit EnforceProposal(4, proposalID, msg.sender, true);
		} else {
			vetoGovTax(proposalID);
		}
    }
	
		    //process for setting deposit fee, funding fee and referral reward	
    function proposeVault(uint256 depositingTokens, uint256 _type, uint256 _amount, uint256 delay) external {	
        require(depositingTokens >= IGovernor(owner()).costToVote(), "Costs to vote");	
        require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");	
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
			
		IVoting(creditContract).deductCredit(msg.sender, withTokens);	
		vaultProposals[proposalID].valueSacrificedForVote+= withTokens;	
				
		emit AddVotes(5, proposalID, msg.sender, withTokens, true);	
	}	
	function voteVaultN(uint256 proposalID, uint256 withTokens, bool withAction) external {	
		require(vaultProposals[proposalID].valid, "invalid");	
			
		IVoting(creditContract).deductCredit(msg.sender, withTokens);	
			
		vaultProposals[proposalID].valueSacrificedAgainst+= withTokens;	
		if(withAction) { vetoVault(proposalID); }	
		emit AddVotes(5, proposalID, msg.sender, withTokens, false);	
	}	
    function vetoVault(uint256 proposalID) public {	
    	require(vaultProposals[proposalID].valid == true, "Invalid proposal"); 	
		require(vaultProposals[proposalID].firstCallTimestamp + vaultProposals[proposalID].delay <= block.timestamp, "pending delay");	
		require(vaultProposals[proposalID].valueSacrificedForVote < vaultProposals[proposalID].valueSacrificedAgainst, "needs more votes");	
			
    	vaultProposals[proposalID].valid = false;	
		emit EnforceProposal(5, proposalID, msg.sender, false);	
    }	
    function executeVault(uint256 proposalID) public {	
    	require(	
    	    vaultProposals[proposalID].valid == true &&	
    	    vaultProposals[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + vaultProposals[proposalID].delay  < block.timestamp,	
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

	// Reduce Allocations if they exceed allowed maximum
	function rebalanceIfPulseAllocationExceedsMaximum() external {
		uint256 _totalAllocation = 0;
		for(uint i=6; i <= 11; i++) {
			_totalAllocation+= poolAllocation[i];
		}

		if(_totalAllocation > maxPulseEcoTotalAllocation) {
			uint256 _exceedsBy = _totalAllocation - maxPulseEcoTotalAllocation;
			for(uint i=6; i <= 11; i++) {
				poolAllocation[i] = (poolAllocation[i] * (maxPulseEcoTotalAllocation - _exceedsBy)) / maxPulseEcoTotalAllocation;
			}
		}
	}

	// Slowly reduce the maximum allocation for distribution to PulseChain ecosystem (more rewards for PulseDAO native miners)
	// reduce by 1% every 7 days
	// Y=9000*(1-0.01)^t
	function reduceMaxPulseAllocation() external {
		require(lastReducePulseAllocation <= block.timestamp - 7 * 86400, "Must wait 7 days");
		lastReducePulseAllocation = block.timestamp;
		maxPulseEcoTotalAllocation = maxPulseEcoTotalAllocation * 99 / 100;
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
