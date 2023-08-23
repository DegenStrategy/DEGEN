// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;

import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IVoting.sol";
import "./interface/IMasterChef.sol";

contract Senate {
	address public immutable token;
	
	address[] public senators;
	
	mapping(address => bool) public isSenator;
	mapping(address => bool) public addedSenator; // prevents double add 
	
	mapping(address => uint256[]) public senatorVotes;
	mapping(uint256 => uint256) public votesForProposal;
	
	uint256 public lastVotingCreditGrant; // timestamp
	uint256 public lastTotalPublished; // record of total published from masterchef
	
	uint256 public maxSenators = 100;
	uint256 public minSenators = 25;
	
	constructor(address _token) {
		token = _token;
	}

	event AddSenator(address senator);
	event RemoveSenator(address senator);
	event AddVote(address voter, uint256 proposalId);
	event RemoveVote(address voter, uint256 proposalId);
	
	function addSenator(address _newSenator) public {
		require(msg.sender == owner(), "only through decentralized voring");
		require(!isSenator[_newSenator], "already a senator!");
		require(!addedSenator[_newSenator], "already added");
		
		senators.push(_newSenator);
		isSenator[_newSenator] = true;
		addedSenator[_newSenator] = true;

		emit AddSenator(_newSenator);
	}
	
	function massAdd(address[] calldata _senators) external {
		for(uint i=0; i < _senators.length; i++) {
			addSenator(_senators[i]);
		}
	}
	
	function expandSenate(address _newSenator) external {
		require(senators.length < maxSenators, "maximum Number of senators achieved");
		require(votesForProposal[toUint(_newSenator)] > senatorCount()/2, "atleast 50% of senate votes required");
		require(!isSenator[_newSenator], "already a senator!");
		require(!addedSenator[_newSenator], "already added");
		
		senators.push(_newSenator);
		isSenator[_newSenator] = true;
		addedSenator[_newSenator] = true;

		emit AddSenator(_newSenator);
	}
	
	function expellSenator(address _senator) external {
		require(senators.length > minSenators, "minimum number of 25 senate members!");
		require(votesForProposal[toUint(_senator)+1] > senatorCount() * 50 / 100, "atleast 50% of senate votes required");
		require(isSenator[_senator], "not a senator!");
		
		isSenator[_senator] = false;

		emit RemoveSenator(_senator);
		
		for(uint i=0; i < senators.length-1; i++) {
			if(senators[i] == _senator) {
				senators[i] = senators[senators.length-1];
				break;
			}
		}
		
		senators.pop();
	}
	
	function selfReplaceSenator(address _newSenator) external {
		require(isSenator[msg.sender], "not a senator");
		require(!isSenator[_newSenator], "already senator");
		require(senatorVotes[msg.sender].length == 0, "can't be participating in a vote during transfer!");
		
		isSenator[msg.sender] = false;
		isSenator[_newSenator] = true;

		emit RemoveSenator(msg.sender);
		emit AddSenator(_newSenator);
		
		for(uint i=0; i < senators.length; i++) {
			if(senators[i] == msg.sender) {
				senators[i] = _newSenator;
				addedSenator[_newSenator] = true;
				break;
			}
		}
	}
	
	function grantVotingCredit() external {
		address _contract = IGovernor(owner()).creditContract();
		address _chef = IMasterChef(owner()).owner();
		
		uint256 _totalPublished = IDTX(token).totalPublished();
		
		uint256 _reward = (_totalPublished - lastTotalPublished) / 100;
		
		lastTotalPublished = _totalPublished;
		// there is a maximum number before gas limit
		for(uint i=0; i < senators.length; i++) {
			IVoting(_contract).addCredit(_reward, senators[i]);
		}
	}

	/* When voting for governor, use the regular proposal ID
	 * When voting for treasury proposals, artifically add +1 to the ID
	 * 
	 */
	function vote(uint256 proposalId) external {
		require(isSenator[msg.sender], "not a senator");
		
		for(uint i=0; i < senatorVotes[msg.sender].length; i++) {
			require(senatorVotes[msg.sender][i] != proposalId, "already voting!");
		}
		
		votesForProposal[proposalId]++;
		senatorVotes[msg.sender].push(proposalId);
		emit AddVote(msg.sender, proposalId);
	}
	
	function removeVote(uint256 proposalId) external {
		require(isSenator[msg.sender], "not a senator");
		
		for(uint i=0; i < senatorVotes[msg.sender].length; i++) {
			if(senatorVotes[msg.sender][i] == proposalId) {
				if(i != senatorVotes[msg.sender].length-1) {
					senatorVotes[msg.sender][i] = senatorVotes[msg.sender][senatorVotes[msg.sender].length-1];
				} 
				senatorVotes[msg.sender].pop();
				
				votesForProposal[proposalId]--;
				emit RemoveVote(msg.sender, proposalId);
				break;
			}
		}
	}

	// For treasury vote, vote for consensus ID, but when pushing...submit regular ID
	function vetoProposal(uint256 consensusProposalId, uint256 treasuryProposalId) external {
		require(votesForProposal[consensusProposalId] > senatorCount()/2, "atleast 50% of senate votes required");
		address _contract = IGovernor(owner()).consensusContract();

		(uint256 _typeOfProposal, , ) = IConsensus(_contract).consensusProposal(consensusProposalId);
		if(_typeOfProposal == 0) {
			IConsensus(_contract).senateVeto(consensusProposalId);
		} else {
			// make sure the user-submitted treasury proposal ID actually matches the consensus proposal ID in the consensus contract
			( , , , , , , , , uint256 _treasuryProposalId) = IConsensus(_contract).treasuryProposal(consensusProposalId);
			require(_treasuryProposalId == treasuryProposalId, " Incorrect proposal! ");
			IConsensus(_contract).senateVetoTreasury(treasuryProposalId);
		}
	}

	function multiCall() public view returns (address[] memory, uint256[][] memory, uint256[] memory, uint256, uint256[] memory) {
		uint256[][] memory allVotes = new uint256[][](senators.length);
		uint256[] memory allCredits = new uint256[](senators.length);
		uint256[] memory mintableCredit = new uint256[](senators.length);

		address _chef = IMasterChef(owner()).owner();

		address _votingContract = IGovernor(owner()).creditContract();
		
		uint256 _totalPublished = IMasterChef(_chef).totalPublished();
		
		uint256 _reward = (_totalPublished - lastTotalPublished) / 100;

		for (uint256 i = 0; i < senators.length; i++) {
			allVotes[i] = senatorVotes[senators[i]];
			allCredits[i] = IVoting(_votingContract).userCredit(senators[i]);
			mintableCredit[i] = IMasterChef(_chef).credit(senators[i]);
		}

		return (senators, allVotes, allCredits, _reward, mintableCredit);
	}
	
	function setSenatorCount(uint256 _min, uint256 _max) external {
		require(msg.sender == owner(), " decentralized voting only! ");
		
		minSenators = _min;
		maxSenators = _max;
	}
	
	function viewSenators() external view returns(address[] memory) {
		return senators;
	}
	
	function senatorCount() public view returns (uint256) {
		return senators.length;
	}
	
	function owner() public view returns (address) {
		return (IDTX(token).governor());
    }
	
	function toUint(address self) public pure returns(uint256) {
		return uint256(uint160(self));
	}
}
