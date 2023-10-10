// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "./interface/IGovernor.sol";
import "./interface/IacPool.sol";
import "./interface/IDTX.sol";
import "./interface/IVoting.sol";


contract DTXconsensus {
    struct TreasuryTransfer {
        bool valid;
        uint256 firstCallTimestamp;
        uint256 valueSacrificedForVote;
		uint256 valueSacrificedAgainst;
		uint256 delay;
		address tokenAddress;
        address beneficiary;
		uint256 amountToSend;
		uint256 consensusProposalID;
    }
	struct ConsensusVote {
        uint16 typeOfChange; // 0 == governor change, 1 == treasury transfer
        address beneficiaryAddress; 
		uint256 timestamp;
    }
	struct GovernorInvalidated {
        bool isInvalidated; 
        bool hasPassed;
    }

	TreasuryTransfer[] public treasuryProposal;
	ConsensusVote[] public consensusProposal;
	
    address public immutable token; //DTX token (address)
	uint256 public governorCount; //count number of proposals
	address private _owner;

	address public creditContract;

    mapping(address => GovernorInvalidated) public isGovInvalidated;
	
	// *kinda* allows voting for multiple proposals
	mapping(uint256 => uint256) public highestConsensusVotes;
    
	constructor(address _DTX) {
		//0 is an invalid proposal(is default / neutral position)
		consensusProposal.push(ConsensusVote(0, address(this), block.timestamp)); 
		token = _DTX;
    }
    
	
	event TreasuryProposal(
		uint256 indexed proposalID,
		uint256 sacrificedTokens, 
		address tokenAddress, 
		address recipient, 
		uint256 amount, 
		uint256 consensusVoteID, 
		address indexed enforcer, 
		uint256 delay
	);
	event TreasuryEnforce(uint256 indexed proposalID, address indexed enforcer, bool isSuccess);
    
    event ProposeGovernor(uint256 proposalID, address newGovernor, address indexed enforcer);
    event ChangeGovernor(uint256 proposalID, address indexed enforcer, bool status);
	
	event AddVotes(
		uint256 _type, 
		uint256 proposalID,  
		address indexed voter, 
		uint256 tokensSacrificed, 
		bool _for
	);
    

     /**
     * Initiates a request to transfer tokens from the treasury wallet
	 * Can be voted against during the "delay before enforce" period
	 * For extra safety
	 * Requires vote from long term stakers to enforce the transfer
	 * Requires 25% of votes to pass
	 * If only 5% of voters disagree, the proposal is rejected
	 *
	 * The possibilities here are endless
	 *
	 * Could act as a NFT marketplace too, could act as a treasury that pays "contractors",..
	 * Since it's upgradeable, this can be added later on anyways....
	 * Should probably make universal private function for Consensus Votes
     */
	function initiateTreasuryTransferProposal(
		uint256 depositingTokens,  
		address tokenAddress, 
		address recipient, 
		uint256 amountToSend, 
		uint256 delay 
	) 
		external 
	{ 
    	require(depositingTokens >= IGovernor(owner()).costToVote() * 100,
    	    "atleast x100minCostToVote"
    	    );
		require(delay <= IGovernor(owner()).delayBeforeEnforce(), 
			"must be shorter than Delay before enforce"
		);
    	
    	IVoting(creditContract).deductCredit(msg.sender, depositingTokens);
		
		uint256 _consensusID = consensusProposal.length;
		
		consensusProposal.push(
		    ConsensusVote(1, address(this), block.timestamp)
		    ); // vote for
    	consensusProposal.push(
    	    ConsensusVote(1, address(this), block.timestamp)
    	    ); // vote against
		
		 treasuryProposal.push(
    	    TreasuryTransfer(
				true, 
				block.timestamp, 
				depositingTokens, 
				0, 
				delay, 
				tokenAddress, 
				recipient, 
				amountToSend, 
				_consensusID
			));  
		   
        emit TreasuryProposal(
            treasuryProposal.length - 1, 
			depositingTokens, 
			tokenAddress, recipient, 
			amountToSend, 
			_consensusID, 
			msg.sender, 
			delay
		);
    }
	
	/* can only vote with tokens during the delay+delaybeforeenforce period
	 *(then this period ends, and to approve the transfer,
	 *  must be voted through voting with locked shares)
	 */
	function voteTreasuryTransferProposalY(uint256 proposalID, uint256 withTokens) external {
		require(treasuryProposal[proposalID].valid, "invalid");
		require(
			(
				treasuryProposal[proposalID].firstCallTimestamp +
				treasuryProposal[proposalID].delay +
				IGovernor(owner()).delayBeforeEnforce()
			)
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);

		treasuryProposal[proposalID].valueSacrificedForVote+= withTokens;

		emit AddVotes(0, proposalID, msg.sender, withTokens, true);
	}
	function voteTreasuryTransferProposalN(
		uint256 proposalID, 
		uint256 withTokens, 
		bool withAction
	) 
		external 
	{
		require(treasuryProposal[proposalID].valid, "invalid");
		require(
			(	treasuryProposal[proposalID].firstCallTimestamp 
				+ treasuryProposal[proposalID].delay 
				+ IGovernor(owner()).delayBeforeEnforce()
			) 
				> block.timestamp,
			"can already be enforced"
		);
		
		IVoting(creditContract).deductCredit(msg.sender, withTokens);
		
		treasuryProposal[proposalID].valueSacrificedAgainst+= withTokens;
		if(withAction) { vetoTreasuryTransferProposal(proposalID); }

		emit AddVotes(0, proposalID, msg.sender, withTokens, false);
	}
    function vetoTreasuryTransferProposal(uint256 proposalID) public {
    	require(treasuryProposal[proposalID].valid == true, "Proposal already invalid");
		require(
			(
				treasuryProposal[proposalID].firstCallTimestamp +
				treasuryProposal[proposalID].delay
			)
				<= block.timestamp,
			"pending delay"
		);
		require(
			(
				treasuryProposal[proposalID].firstCallTimestamp +
				treasuryProposal[proposalID].delay +
				IGovernor(owner()).delayBeforeEnforce() 
			)
				>= block.timestamp,
			"past the point of no return"
		);
    	require(
			treasuryProposal[proposalID].valueSacrificedForVote 
			< treasuryProposal[proposalID].valueSacrificedAgainst,
				"needs more votes");
		
    	treasuryProposal[proposalID].valid = false;  
		
    	emit TreasuryEnforce(proposalID, msg.sender, false);
    }
    /*
    * After delay+delayBeforeEnforce , the proposal effectively passes 
	* to be voted through consensus (token voting stops, voting with locked shares starts)
	* Another delayBeforeEnforce period during which users can vote with locked shares
    */
	function approveTreasuryTransfer(uint256 proposalID) public {
		require(treasuryProposal[proposalID].valid, "Proposal already invalid");
		uint256 consensusID = treasuryProposal[proposalID].consensusProposalID;
		updateHighestConsensusVotes(consensusID);
		updateHighestConsensusVotes(consensusID+1);
		require(
			treasuryProposal[proposalID].firstCallTimestamp + 
			treasuryProposal[proposalID].delay + 
			2 * IGovernor(owner()).delayBeforeEnforce() <= block.timestamp,
			"Enough time must pass before enforcing"
		);
		
		uint256 _totalStaked = totalDTXStaked();
		uint256 _castedInFavor = highestConsensusVotes[consensusID];
		if(treasuryProposal[proposalID].valueSacrificedForVote >= treasuryProposal[proposalID].valueSacrificedAgainst &&
				_castedInFavor >= _totalStaked * 15 / 100 ) {
			
			//just third of votes voting against(a third of those in favor) kills the treasury withdrawal
			if(highestConsensusVotes[consensusID+1] >= _castedInFavor * 33 / 100) { 
				treasuryProposal[proposalID].valid = false;
				emit TreasuryEnforce(proposalID, msg.sender, false);
			} else {
				IGovernor(owner()).treasuryRequest(
					treasuryProposal[proposalID].tokenAddress, 
					treasuryProposal[proposalID].beneficiary, 
					treasuryProposal[proposalID].amountToSend
				 );
				treasuryProposal[proposalID].valid = false;  
				
				emit TreasuryEnforce(proposalID, msg.sender, true);
			}
		} else {
			treasuryProposal[proposalID].valid = false;  
		
			emit TreasuryEnforce(proposalID, msg.sender, false);
		}
	}
	
	 /**
     * Kills treasury transfer proposal if more than 15% of weighted vote(of total staked)
     */
	function killTreasuryTransferProposal(uint256 proposalID) external {
		require(treasuryProposal[proposalID].valid, "Proposal already invalid");
		uint256 consensusID = treasuryProposal[proposalID].consensusProposalID;
		
        require(
            tokensCastedPerVote(consensusID+1) >= totalDTXStaked() * 15 / 100,
				"15% weigted vote (voting against) required to kill the proposal"
        );
		
    	treasuryProposal[proposalID].valid = false;  
		
    	emit TreasuryEnforce(proposalID, msg.sender, false);
	}
	
	//updates highest votes collected
	function updateHighestConsensusVotes(uint256 consensusID) public {
		uint256 _current = tokensCastedPerVote(consensusID);
		if(_current > highestConsensusVotes[consensusID]) {
			highestConsensusVotes[consensusID] = _current;
		}
	}
	
	
    function proposeGovernor(address _newGovernor) external {
		require(isContract(_newGovernor), "Address must be a contract!");
		governorCount++;
		IVoting(creditContract).deductCredit(msg.sender, IGovernor(owner()).costToVote() * 100);
		
		consensusProposal.push(
    	    ConsensusVote(0, _newGovernor, block.timestamp)
    	    );
    	consensusProposal.push(
    	    ConsensusVote(0, _newGovernor, block.timestamp)
    	    ); //even numbers are basically VETO (for voting against)
    	
    	emit ProposeGovernor(consensusProposal.length - 2, _newGovernor, msg.sender);
    }
    
    /**
     * Atleast 15% of voters required
     * with 75% agreement required to reach consensus
	 * After proposing Governor, a period of time(delayBeforeEnforce) must pass 
	 * During this time, the users can vote in favor(proposalID) or against(proposalID+1)
	 * If voting succesfull, it can be submitted
	 * And then there is a period of roughly 6 days(specified in governing contract) before the change can be enforced
	 * During this time, users can still vote and reject change
	 * Unless rejected, governing contract can be updated and changes enforced
     */
    function changeGovernor(uint256 proposalID) external { 
		require(
			block.timestamp >= (consensusProposal[proposalID].timestamp + IGovernor(owner()).delayBeforeEnforce()), 
			"Must wait delay before enforce"
		);
        require(
			!(isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated), 
			" alreadyinvalidated"
		);
		require(
			!(isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].hasPassed), 
			" already passed")
		;
		require(
			consensusProposal.length > proposalID && proposalID % 2 == 1, 
			"invalid proposal ID"
		); //can't be 0 either, but %2 solves that
        require(!(IGovernor(owner()).changeGovernorActivated()));
		require(consensusProposal[proposalID].typeOfChange == 0);

        require(
            tokensCastedPerVote(proposalID) >= totalDTXStaked() * 15 / 100,
				"Requires atleast 15% of staked(weighted) tokens"
        );

        //requires 2/3 agreement amongst votes (+senate can reject)
        if(tokensCastedPerVote(proposalID+1) >= tokensCastedPerVote(proposalID) / 3) {
            
                isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated = true;
                
				emit ChangeGovernor(proposalID, msg.sender, false);
				
            } else {
                IGovernor(owner()).setNewGovernor(consensusProposal[proposalID].beneficiaryAddress);
                
                isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].hasPassed = true;
                
                emit ChangeGovernor(proposalID, msg.sender, true);
            }
    }
    
    /**
     * After approved, still roughly 6 days to cancle the new governor, if less than 80% votes agree
	 * 6 days at beginning in case we need to make changes on the fly, and later on the period should be increased
	 * Note: The proposal IDs here are for the consensus ID
	 * After rejecting, call the governorRejected in governing contract(sets activated setting to false)
     */
    function vetoGovernor(uint256 proposalID, bool _withUpdate) external {
        require(proposalID % 2 == 1, "Invalid proposal ID");
        require(isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].hasPassed ,
					"Governor has already been passed");
		require(!isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated,
					"Governor has already been invalidated");

        if(tokensCastedPerVote(proposalID+1) >= tokensCastedPerVote(proposalID) / 5) {
              isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated = true;
			  emit ChangeGovernor(proposalID, msg.sender, false);

			  if(_withUpdate) { IGovernor(owner()).governorRejected(); }
        }
    }
	//even if not approved, can be cancled at any time if 25% of weighted votes go AGAINST
    function vetoGovernor2(uint256 proposalID, bool _withUpdate) external {
        require(proposalID % 2 == 1, "Invalid proposal ID");

		//25% of weighted total vote AGAINST kills the proposal as well
        if(tokensCastedPerVote(proposalID+1) >= totalDTXStaked() * 25 / 100) {
              isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated = true;
			  emit ChangeGovernor(proposalID, msg.sender, false);

			  if(_withUpdate) { IGovernor(owner()).governorRejected(); }
        }
    }
    function enforceGovernor(uint256 proposalID) external {
		//proposal ID = 0 is neutral position and not allowed(%2 applies)
        require(proposalID % 2 == 1, "invalid proposal ID"); 
        require(!isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated, "invalid");
        
        require(consensusProposal[proposalID].beneficiaryAddress == IGovernor(owner()).eligibleNewGovernor());
      
	  	IGovernor(owner()).enforceGovernor();
	  
        isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated = true;
    }
   
    function senateVeto(uint256 proposalID) external {
		require(msg.sender == IGovernor(owner()).senateContract(), " veto allowed only by senate ");
		require(proposalID % 2 == 1, "Invalid proposal ID");

		require(!isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated);

	    isGovInvalidated[consensusProposal[proposalID].beneficiaryAddress].isInvalidated = true;
	    emit ChangeGovernor(proposalID, tx.origin, false);
	}

	function senateVetoTreasury(uint256 proposalID) external {
		require(msg.sender == IGovernor(owner()).senateContract(), " veto allowed only by senate ");

		require(treasuryProposal[proposalID].valid, "Proposal already invalid");

    	treasuryProposal[proposalID].valid = false;  
		
    	emit TreasuryEnforce(proposalID, tx.origin, false);
	}

	function syncOwner() external {
		_owner = IDTX(token).governor();
    }

	function syncCreditContract() external {
		creditContract = IGovernor(owner()).creditContract();
	}

	function treasuryRequestsCount() external view returns (uint256) {
		return treasuryProposal.length;
	}

	/**
	 * Can be used for building database from scratch (opposed to using event logs)
	 * also to make sure all data and latest events are synced correctly
	 */
	function proposalLengths() external view returns(uint256, uint256) {
		return(treasuryProposal.length, consensusProposal.length);
	}

	//masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return _owner;
    }

    /**
     * Returns total DTX staked accross all pools.
     */
    function totalDTXStaked() public view returns(uint256) {
    	return (
			IacPool(IGovernor(owner()).acPool1()).balanceOf() + 
			IacPool(IGovernor(owner()).acPool2()).balanceOf() +
			IacPool(IGovernor(owner()).acPool3()).balanceOf() +
			IacPool(IGovernor(owner()).acPool4()).balanceOf() + 
			IacPool(IGovernor(owner()).acPool5()).balanceOf() + 
			IacPool(IGovernor(owner()).acPool6()).balanceOf()
		);
    }

    /**
     * Gets DTX allocated per vote with ID for each pool
     * Process:
     * Gets votes for ID and calculates DTX equivalent
     * ...and assigns weights to votes
     * Pool1(20%), Pool2(30%), Pool3(50%), Pool4(75%), Pool5(115%), Pool6(150%)
     */
    function tokensCastedPerVote(uint256 _forID) public view returns(uint256) {
        return (
            IacPool(IGovernor(owner()).acPool1()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool1()).getPricePerFullShare() / 1e19 * 2 + 
                IacPool(IGovernor(owner()).acPool2()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool2()).getPricePerFullShare() / 1e19 * 3 +
                    IacPool(IGovernor(owner()).acPool3()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool3()).getPricePerFullShare() / 1e19 * 5 +
                        IacPool(IGovernor(owner()).acPool4()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool4()).getPricePerFullShare() / 1e20 * 75 +
                            IacPool(IGovernor(owner()).acPool5()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool5()).getPricePerFullShare() / 1e20 * 115 +
                                IacPool(IGovernor(owner()).acPool6()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool6()).getPricePerFullShare() / 1e19 * 15
        );
    }

	function isContract(address _address) public view returns (bool) {
	    uint256 codeSize;
	    assembly {
		codeSize := extcodesize(_address)
	    }
	    return (codeSize > 0);
	}
}
