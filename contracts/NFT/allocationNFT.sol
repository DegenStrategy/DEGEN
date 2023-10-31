// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "../interface/IGovernor.sol";
import "../interface/IDTX.sol";
import "../interface/IConsensus.sol";
import "../interface/IVoting.sol";

interface IAllocation {
    function nftAllocation(address _tokenAddress, uint256 _tokenID) external view returns (uint256);
}


/*
 * TLDR of how it works;
 * If threshold of vote is met(through stake voting), the proposal can be pushed
 * Proposal can be rejected if reject threshold is met
 * If not rejected during rejection period, the proposed contract goes into effect
 * The proposed contract should contain the logic and details for actual allocations per each NFT
 * This contract acts as a proxy for the staking contract(staking contract looks up allocation through this contract)
 * And this contract looks up the actual allocation number through the valid allocation contract
 * Can contain a batch/list of NFTs, process for changing allocations, etc...
*/
contract DTXNFTallocationProxy {
    struct PendingContract {
        bool isValid;
        uint256 timestamp;
        uint256 votesCommitted;
    }

	address private _owner;

    address public immutable token;
	
	address public creditContract;

    uint256 public approveThreshold = 100; // percentage required to approve (100=10%)
    uint256 public rejectThreshold = 500; // percentage required to reject (of maximum vote allocated)
    uint256 public rejectionPeriod = 7 days; // period during which the allocation contract can be rejected(after approval)

    mapping(address => bool) public allocationContract; 
    mapping(address => PendingContract) public pendingContract; 
    
    constructor(address _dtx) {
        token = _dtx;
    }

    event SetAllocationContract(address indexed contractAddress, bool setting);
    event SetPendingContract(address indexed contractAddress, uint256 uintValue, bool setting);
    event UpdateVotes(address indexed contractAddress, uint256 uintValue, uint256 weightedVote);
    event NotifyVote(address indexed _contract, uint256 uintValue, address indexed enforcer);

    function getAllocation(address _tokenAddress, uint256 _tokenID, address _allocationContract) external view returns (uint256) {
        uint256 _alloc = IAllocation(_allocationContract).nftAllocation(_tokenAddress, _tokenID);
	if(allocationContract[_allocationContract]) { //allocation must be equal or greater than 1e18
            return _alloc;
        } else {
            return 0;
        }
    }

    // notify "start of voting" on the frontend
	// serves as signal to other users to help accumulate votes in favor
    function notifyVote(address _contract) external {
    	require(isContract(_contract), "Address must be a contract!");
    	IVoting(creditContract).deductCredit(msg.sender, IGovernor(owner()).costToVote() * 50);

		uint256 _check = IAllocation(_contract).nftAllocation(address(this), 0); // Check for compatibility
        emit NotifyVote(_contract, addressToUint256(_contract), msg.sender);
    }

	//IMPORTANT: allocations have to be atleast 1e18, ideally greater!
    function proposeAllocationContract(address _contract) external {
		require(isContract(_contract), "Address must be a contract!");
        require(!pendingContract[_contract].isValid, "already proposing");
		require(block.timestamp > pendingContract[_contract].timestamp, "cool-off period required"); //in case contract is rejected
        uint256 _contractUint = addressToUint256(_contract);
        require(!pendingContract[address(uint160(_contractUint-1))].isValid, "trying to submit veto as a proposal");
        address _consensusContract = IGovernor(IDTX(token).governor()).consensusContract();

        uint256 _threshold = IConsensus(_consensusContract).totalDTXStaked() * approveThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = true;
        pendingContract[_contract].timestamp = block.timestamp + 3 days;
        pendingContract[_contract].votesCommitted = _weightedVote;

        emit SetPendingContract(_contract, _contractUint, true);
    }
    //votes commited parameter is the highest achieved
    function updateVotes(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
  
        uint256 _contractUint = addressToUint256(_contract);
        address _consensusContract = IGovernor(IDTX(token).governor()).consensusContract();
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > pendingContract[_contract].votesCommitted, "can only update to higher vote count");

        pendingContract[_contract].votesCommitted = _weightedVote;
        
        emit UpdateVotes(_contract, _contractUint, _weightedVote);
    }

    function rejectAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid, "proposal not valid");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IGovernor(IDTX(token).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);

        require(_weightedVote > _threshold, "insufficient votes committed");

        pendingContract[_contract].isValid = false;
		pendingContract[_contract].votesCommitted = 0;
		pendingContract[_contract].timestamp = block.timestamp + 259200; //3-day cool-off period

        emit SetPendingContract(_contract, _contractUint-1, false);
    }

    function approveAllocationContract(address _contract) external {
        require(pendingContract[_contract].isValid && !allocationContract[_contract], "contract not approved or already approved");
        require(block.timestamp > (pendingContract[_contract].timestamp + rejectionPeriod), "must wait rejection period before approval");
        uint256 _contractUint = addressToUint256(_contract) + 1; //+1 to vote against
        address _consensusContract = IGovernor(IDTX(token).governor()).consensusContract();

        uint256 _threshold = pendingContract[_contract].votesCommitted * rejectThreshold / 1000;
        uint256 _weightedVote = IConsensus(_consensusContract).tokensCastedPerVote(_contractUint);
        if(_weightedVote > _threshold) { //reject
            pendingContract[_contract].isValid = false;
            emit SetPendingContract(_contract, _contractUint-1, false);
        } else { //enforce
            allocationContract[_contract] = true;
			pendingContract[_contract].isValid = false;

			emit SetPendingContract(_contract, _contractUint-1, true);
            emit SetAllocationContract(_contract, true);
        }
    }

    //allocation contract can also be set through the governing address
    function setAllocationContract(address _contract, bool _setting) external {
        require(msg.sender == IDTX(token).governor(), "only governor");
        allocationContract[_contract] = _setting;

        emit SetAllocationContract(_contract, _setting);
    }

    function setApproveThreshold(uint256 _threshold) external {
        require(msg.sender == IDTX(token).governor(), "only governor");
        approveThreshold = _threshold;
    }
    function setRejectThreshold(uint256 _threshold) external {
        require(msg.sender == IDTX(token).governor(), "only governor");
        rejectThreshold = _threshold;
    }
    function setRejectionPeriod(uint256 _period) external {
        require(msg.sender == IDTX(token).governor(), "only governor");
        rejectionPeriod = _period;
    }

	function syncOwner() external {
		_owner = IDTX(token).governor();
    	}

	function syncCreditContract() external {
		creditContract = IGovernor(owner()).creditContract();
	}

	function owner() public view returns (address) {
		return _owner;
    	}
	
	function isContract(address _address) public view returns (bool) {
	    uint256 codeSize;
	    assembly {
		codeSize := extcodesize(_address)
	    }
	    return (codeSize > 0);
	}

	function addressToUint256(address _address) public pure returns (uint256) {
        return(uint256(uint160(_address)));
    }
}
