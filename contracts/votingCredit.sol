// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

import "./interface/IDTX.sol";
import "./interface/IMasterChef.sol";

contract VotingCredit {
	IDTX public immutable token;
	IMasterChef public masterchef;
	
	address public immutable airdropContract = ;
	address public immutable airdropContractFull = ; //no penalty
	
	mapping(address => uint256) public userCredit;
	
	//crediting are contracts that deposit(pools + NFT staking)
	mapping(address => bool) public creditingContract;
	uint256 public creditingContractCount;
	
	//deducting are the side contracts(rewardBoost, farms, NFTallocation, consensus, basic)
	mapping(address => bool) public deductingContract;
	uint256 public deductingContractCount;
	
	// allows for custom implementations
	mapping(uint256 => uint256) public burnedForId;
	
	constructor(IDTX _token, IMasterChef _masterchef, uint256 _creditingContractCount, uint256 _deductingContractCount, address _airdropContract, address _airdropContractFull) {
		token = _token;
		masterchef = _masterchef;
		creditingContractCount = _creditingContractCount; //6
		deductingContractCount = _deductingContractCount; //5
		creditingContract[""] = true; // set for all crediting contracts (all staking pools)
		creditingContract[""] = true;
		creditingContract[""] = true;
		creditingContract[""] = true;
		creditingContract[""] = true;
		creditingContract[""] = true;
		deductingContract[""] = true; // set for all deducting contracts (rewardBoost, consensus, basicSettings, farms, nftAllocation)
		deductingContract[""] = true;
		deductingContract[""] = true;
		deductingContract[""] = true;
		deductingContract[""] = true;
		airdropContract = _airdropContract; // With token penalty on deposit to lower timeframe stakes
		airdropContractFull = _airdropContractFull; // No penalties for tokens (credit received is lesser on shorter timeframe stake)
	}
	
	event SetCreditingContract(address _contract, bool setting);
	event SetDeductingContract(address _contract, bool setting);
	event AddCredit(address indexed depositor, uint256 amount);
	event BurnCredit(address burnFrom, uint256 amount, uint256 forId);
	
	// WARNING: the deductingContract should ALWAYS and only set the msg.sender as "address from"
	// This is the condition to be added as a deductingContract
	function deductCredit(address from, uint256 amount) public returns (bool) {
		require(deductingContract[msg.sender], "invalid sender, trusted contracts only");
		
		if(userCredit[from] >= amount) {
			userCredit[from]-= amount;
		} else {
			require(masterchef.burn(from, amount));
		}
		return true;
	}
	
	//not emitting events, can see them on the crediting contract side
	// all pools + NFT staking contract have to be marked as "creditingContracts"
	// the crediting contract transfers the tokens to the treasury and then calls addCredit
	function addCredit(uint256 amount, address _beneficiary) external {
		require(creditingContract[msg.sender], "invalid sender, trusted contracts only");
		userCredit[_beneficiary]+=amount;
	}
	
	//manually deposit tokens to get voting credit
	function depositCredit(uint256 amount) external {
		require(masterchef.burn(msg.sender, amount));
		userCredit[msg.sender]+=amount;
		emit AddCredit(msg.sender, amount);
	}
	
	function airdropVotingCredit(uint256 amount, address beneficiary) external {
		require(msg.sender== airdropContract || msg.sender == airdropContractFull, "no permission");
		userCredit[beneficiary]+=amount;
		emit AddCredit(beneficiary, amount);
	}
	
	function burnCredit(uint256 amount, uint256 _forId) external {
		userCredit[msg.sender] = userCredit[msg.sender] - amount;
		burnedForId[_forId]+= amount;
		
		emit BurnCredit(msg.sender, amount, _forId);
	}
	
	//add/remove contracts
	function modifyCreditingContract(address _contract, bool setting) external {
        require(msg.sender == owner(), "decentralized voting required");
		if(creditingContract[_contract] != setting) {
			creditingContract[_contract] = setting;
			setting ? creditingContractCount++ : creditingContractCount--;
			
			emit SetCreditingContract(_contract, setting);
		}
	}
	
	//add/remove contracts
	function modifyDeductingContract(address _contract, bool setting) external {
        require(msg.sender == owner(), "decentralized voting required");
		if(deductingContract[_contract] != setting) {
			deductingContract[_contract] = setting;
			setting ? deductingContractCount++ : deductingContractCount--;
			
			emit SetDeductingContract(_contract, setting);
		}
	}
	
	// publishes rightful tokens to governor contract
	function redeemGovernor() external {
		masterchef.publishToken(owner(), masterchef.credit(address(this)));
	}
	
	function updateChef() external {
		masterchef = IMasterChef(token.owner());
	}
	
	function owner() public view returns (address) {
		return token.governor();
	}
}
