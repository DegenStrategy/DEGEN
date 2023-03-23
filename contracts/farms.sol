// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

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
    
    address public immutable token; //DTX token(address!)
	
	address public creditContract;
	
	address public masterchef;
    
	uint256 public maxLpAllocation = 1250;
	uint256 public maxNftAllocation = 1000;
	
	uint256 public maxPulseEcoAllocation = 2000; //max 20% per pool
	uint256 public maxPulseEcoTotalAllocation = 5000; // max 50% total
    bool public isReductionEnforced; 
    
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
    
	constructor (address _DTX, address _masterchef)  {
		token = _DTX;
		masterchef = _masterchef;
	}

	//ability to change max allocations without launching new contract
	function changeMaxAllocations(uint256 _lp, uint256 _nft, uint256 _maxPulse, uint256 _maxPulseTotal) external {
        require(msg.sender == owner(), "owner only");
		maxLpAllocation = _lp;
		maxNftAllocation = _nft;
        maxPulseEcoAllocation = _maxPulse;
        maxPulseEcoTotalAllocation = _maxPulseTotal;
	}
    
    /**
     * Regulatory process to regulate farm rewards 
     * And Meme pools
    */    
    function initiateFarmProposal(
            uint256 depositingTokens, uint256 poolid, uint256 newAllocation, uint16 depositFee, uint256 delay
        ) external { 
    	require(delay <= IGovernor(owner()).delayBeforeEnforce(), "must be shorter than Delay before enforce");
    	require(depositingTokens >= IGovernor(owner()).costToVote(), "there is a minimum cost to vote");
    	require(poolid == 0 || poolid == 1 || poolid >= 8 && poolid <= 15, "only allowed for these pools"); 
		
		//0,1,8,9 are  DTX lp pools
		//10 is for NFT staking(nfts and virtual land)
    	if(poolid == 0 || poolid == 1) {
    	    require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * maxLpAllocation / 10000),
    	        "exceeds max allocation"
    	       );
    	} else if(poolid == 10) {
			require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * maxNftAllocation / 10000),
    	        "exceeds max allocation"
    	       );
			require(depositFee == 0, "deposit fee must be 0 for NFTs");
		} else {
    	    require(
    	        newAllocation <= (IMasterChef(masterchef).totalAllocPoint() * maxPulseEcoAllocation / 10000),
    	        "exceeds max allocation"
    	       ); 
    	}
    
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens); 
    	proposalFarmUpdate.push(
    	    ProposalFarm(true, poolid, newAllocation, depositingTokens, 0, delay, block.timestamp, depositFee)
    	    ); 
    	emit InitiateFarmProposal(proposalFarmUpdate.length - 1, depositingTokens, poolid, newAllocation, depositFee, msg.sender, delay);
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
    function updateFarm(uint256 proposalID) public {
        require(!isReductionEnforced, "reward reduction is active"); //only when reduction is not enforced
        require(proposalFarmUpdate[proposalID].valid, "invalid proposal");
        require(
            proposalFarmUpdate[proposalID].firstCallTimestamp + IGovernor(owner()).delayBeforeEnforce() + proposalFarmUpdate[proposalID].delay  < block.timestamp,
            "delay before enforce not met"
            );
		uint256 _poolID = proposalFarmUpdate[proposalID].poolid;
		uint256 _pulseEcoCount = 0;
		uint256 _newAllocation = proposalFarmUpdate[proposalID].newAllocation;
        
		if(proposalFarmUpdate[proposalID].valueSacrificedForVote >= proposalFarmUpdate[proposalID].valueSacrificedAgainst) {
			if(_poolID > 10 && _poolID <= 15) { //for pulse ecosystem
				for(uint256 i= 11; i<=15; i++) {
					if(_poolID != i) { 
						(, uint256 _allocPoint, , , ) = IMasterChef(masterchef).poolInfo(i);
						_pulseEcoCount+= _allocPoint;
					} else {
						_pulseEcoCount+= _newAllocation;
					}
				}
				require(_pulseEcoCount <= (IMasterChef(masterchef).totalAllocPoint() * maxPulseEcoTotalAllocation / 10000), "exceeds maximum allowed allocation for pulse ecosystem");
			}
			IGovernor(owner()).setPool(_poolID, _newAllocation, proposalFarmUpdate[proposalID].newDepositFee, true);
			proposalFarmUpdate[proposalID].valid = false;
			
			emit EnforceProposal(0, proposalID, msg.sender, true);
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
				IGovernor(owner()).burnTokens(governorTransferProposals[proposalID].proposedValue);
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
		address _chefo = IMasterChef(token).owner();
		
        masterchef = _chefo;
    }
   
    //transfers ownership of this contract to new governor
    //masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return IDTX(token).governor();
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
	
		    //process for setting deposit fee, funding fee and referral commission	
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
		if(withAction) { vetoGovernorTransfer(proposalID); }	
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
}
