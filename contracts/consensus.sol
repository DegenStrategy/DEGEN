// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "./interface/IGovernor.sol";
import "./interface/IacPool.sol";
import "./interface/IDTX.sol";
import "./interface/IVoting.sol";
import "./interface/IConsensus.sol";


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

	TreasuryTransfer[] public treasuryProposal;
	ConsensusVote[] public consensusProposal;

	address public constant OINK = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public immutable token = ; //DTX token (address)
	uint256 public governorCount; //count number of proposals
	address private _owner;

	address public creditContract;
	uint256 public OFFSET = 100000000000000000000000000000; // offset to be used for OINK voting

	
	// *kinda* allows voting for multiple proposals
	mapping(uint256 => uint256) public highestConsensusVotes;
    
	constructor() {
		//0 is an invalid proposal(is default / neutral position)
		consensusProposal.push(ConsensusVote(0, address(this), block.timestamp)); 
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
		
		uint256 _totalStaked = IConsensus(getOinkConsensusContract()).totalDTXStaked();
		uint256 _castedInFavor = IConsensus(getOinkConsensusContract()).highestConsensusVotes(consensusID+OFFSET);
		if(treasuryProposal[proposalID].valueSacrificedForVote >= treasuryProposal[proposalID].valueSacrificedAgainst &&
				_castedInFavor >= _totalStaked * 15 / 100 ) {
			
			//just third of votes voting against(a third of those in favor) kills the treasury withdrawal
			if(IConsensus(getOinkConsensusContract()).highestConsensusVotes(consensusID+1+OFFSET) >= _castedInFavor * 33 / 100) { 
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
		updateHighestConsensusVotes(consensusID+1);
		
        require(
            highestConsensusVotes[consensusID+1] >= totalDTXStaked() * 15 / 100,
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
			IacPool(IGovernor(owner()).acPool4()).balanceOf() 
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
                        IacPool(IGovernor(owner()).acPool3()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool3()).getPricePerFullShare() / 1e20 * 60 +
                            IacPool(IGovernor(owner()).acPool4()).totalVotesForID(_forID) * IacPool(IGovernor(owner()).acPool4()).getPricePerFullShare() / 1e19 * 15 
        );
    }


	function getOinkConsensusContract() public view returns(address) {
		return IGovernor(IDTX(OINK).governor()).consensusContract();
	}

	function isContract(address _address) public view returns (bool) {
	    uint256 codeSize;
	    assembly {
		codeSize := extcodesize(_address)
	    }
	    return (codeSize > 0);
	}
}
