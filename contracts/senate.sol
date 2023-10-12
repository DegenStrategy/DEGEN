// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IVoting.sol";
import "./interface/IMasterChef.sol";

contract Senate {
	address public immutable token;
	address private _owner;
	address private immutable deployer;
	
	address[] public senators;
	
	mapping(address => bool) public isSenator;
	mapping(address => bool) public addedSenator; // prevents double add 
	
	mapping(address => uint256[]) public senatorVotes;
	mapping(uint256 => uint256) public votesForProposal;
	
	uint256 public lastTotalCreditGiven; // record of total credit given in masterchef
	
	uint256 public maxSenators = 100;
	uint256 public minSenators = 20;
	
	constructor(address _token) {
		token = _token;
		deployer = msg.sender;
	}

	event AddSenator(address indexed senator);
	event RemoveSenator(address indexed senator);
	event AddVote(address indexed voter, uint256 indexed proposalId);
	event RemoveVote(address indexed voter, uint256 indexed proposalId);
	event UpdateSenatorCount(uint256 minimum, uint256 maximum);
	
	function addSenator(address _newSenator) external {
		require(msg.sender == owner(), "only through decentralized voting");
		require(!isSenator[_newSenator], "already a senator!");
		require(!addedSenator[_newSenator], "already added");

		_addSenator(_newSenator);
	}
	
	
	function expandSenate(address _newSenator) external {
		require(senators.length < maxSenators, "maximum Number of senators achieved");
		require(votesForProposal[toUint(_newSenator)] > senatorCount()/2, "atleast 50% of senate votes required");
		require(!isSenator[_newSenator], "already a senator!");
		require(!addedSenator[_newSenator], "already added");

		_addSenator(_newSenator);
	}
	
	function expellSenator(address _senator, uint256 _senatorId) external {
		require(senators[_senatorId] == _senator, "Senator ID does not match provided senator!");
		require(senators.length > minSenators, "below minimum number of senate members!");
		require(votesForProposal[toUint(_senator)+1] > senatorCount() / 2, "atleast 50% of senate votes required");
		require(isSenator[_senator], "not a senator!");
		
		isSenator[_senator] = false;

		emit RemoveSenator(_senator);

		senators[_senatorId] = senators[senators.length-1];
		senators.pop();
	}
	
	function selfReplaceSenator(address _newSenator, uint256 _senatorId) external {
		require(senators[_senatorId] == _newSenator, "Senator ID does not match provided senator!");
		require(isSenator[msg.sender], "not a senator");
		require(!addedSenator[_newSenator], "already senator");
		require(senatorVotes[msg.sender].length == 0, "can't be participating in a vote during transfer!");
		
		isSenator[msg.sender] = false;
		isSenator[_newSenator] = true;

		emit RemoveSenator(msg.sender);
		emit AddSenator(_newSenator);
		
		senators[_senatorId] = _newSenator;
		addedSenator[_newSenator] = true;
	}
	
	function grantVotingCredit() external {
		address _contract = IGovernor(owner()).creditContract();
		address _chef = IDTX(token).owner();
		
		uint256 _totalGiven = IMasterChef(_chef).totalCreditRewards();
		
		uint256 _reward = (_totalGiven - lastTotalCreditGiven) / 100;
		
		lastTotalCreditGiven = _totalGiven;
		// there is a maximum number before gas limit
		for(uint i=0; i < senators.length; ++i) {
			IVoting(_contract).addCredit(_reward, senators[i]);
		}
	}

	/* When voting for governor, use the regular proposal ID
	 * When voting for treasury proposals, artifically add +1 to the ID
	 * 
	 */
	function vote(uint256 proposalId) external {
		require(isSenator[msg.sender], "not a senator");
		
		for(uint i=0; i < senatorVotes[msg.sender].length; ++i) {
			require(senatorVotes[msg.sender][i] != proposalId, "already voting!");
		}
		
		votesForProposal[proposalId]++;
		senatorVotes[msg.sender].push(proposalId);
		emit AddVote(msg.sender, proposalId);
	}
	
	function removeVote(uint256 proposalId, uint256 _indexId) external {
		require(isSenator[msg.sender], "not a senator");
		require(senatorVotes[msg.sender][_indexId] == proposalId, "incorrect ID");
		
		senatorVotes[msg.sender][_indexId] = senatorVotes[msg.sender][senatorVotes[msg.sender].length-1];

		senatorVotes[msg.sender].pop();
		
		votesForProposal[proposalId]--;
		emit RemoveVote(msg.sender, proposalId);
	}

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
	
	function setSenatorCount(uint256 _min, uint256 _max) external {
		require(msg.sender == owner(), " decentralized voting only! ");
		
		minSenators = _min;
		maxSenators = _max;

		emit UpdateSenatorCount(minSenators, maxSenators);
	}

	function initializeSenators(address[] calldata _senators) external {
		require(msg.sender == deployer, "deployer only!");
		require(senators.length == 0, "already initialized!");
		for (uint256 i = 0; i < _senators.length; ++i) {
			_addSenator(_senators[i]);
		}
	}

	function multiCall() external view returns (address[] memory, uint256[][] memory, uint256[] memory, uint256, uint256[] memory) {
		uint256[][] memory allVotes = new uint256[][](senators.length);
		uint256[] memory allCredits = new uint256[](senators.length);
		uint256[] memory mintableCredit = new uint256[](senators.length);

		address _chef = IDTX(token).owner();

		address _votingContract = IGovernor(owner()).creditContract();
		
		uint256 _totalGiven = IMasterChef(_chef).totalCreditRewards();
		
		uint256 _reward = (_totalGiven - lastTotalCreditGiven) / 100;

		for (uint256 i = 0; i < senators.length; ++i) {
			allVotes[i] = senatorVotes[senators[i]];
			allCredits[i] = IVoting(_votingContract).userCredit(senators[i]);
			mintableCredit[i] = IMasterChef(_chef).credit(senators[i]);
		}

		return (senators, allVotes, allCredits, _reward, mintableCredit);
	}
	
	function viewSenators() external view returns(address[] memory) {
		return senators;
	}
	
	function syncOwner() external {
		_owner = IDTX(token).governor();
    }

	function senatorCount() public view returns (uint256) {
		return senators.length;
	}
	
    function owner() public view returns (address) {
		return _owner;
    }
	
	function toUint(address self) public pure returns(uint256) {
		return uint256(uint160(self));
	}

	function _addSenator(address _senator) private {
		senators.push(_senator);
		isSenator[_senator] = true;
		addedSenator[_senator] = true;
		emit AddSenator(_senator);
	}
}
