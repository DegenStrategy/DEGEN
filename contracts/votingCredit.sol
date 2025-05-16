// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "./interface/IDTX.sol";
import "./interface/IMasterChef.sol";

contract VotingCredit {
	IDTX public immutable token;
	IMasterChef public masterchef;
	address private _owner;
	
	address public immutable airdropContract;
	address public immutable airdropContractLocked;
	
	mapping(address => uint256) public userCredit;
	mapping(address => uint256) public addedCredit;
	
	//crediting are contracts that deposit(pools + NFT staking)
	mapping(address => bool) public creditingContract;
	uint256 public creditingContractCount;
	
	//deducting are the side contracts(rewardBoost, farms, NFTallocation, consensus, basic)
	mapping(address => bool) public deductingContract;
	uint256 public deductingContractCount;
	
	// allows for custom implementations
	mapping(uint256 => uint256) public burnedForId;
	
	constructor(IDTX _token, IMasterChef _masterchef) {
		token = _token;
		masterchef = _masterchef;
		deductingContractCount = 5; 
		deductingContract[] = true; // set for all deducting contracts (rewardBoost, consensus, basicSettings, farms, nftAllocation)
		deductingContract[] = true;
		deductingContract[] = true;
		deductingContract[] = true;
		deductingContract[] = true;
	}
	
	event SetCreditingContract(address indexed _contract, bool setting);
	event SetDeductingContract(address indexed _contract, bool setting);
	event AddCredit(address indexed depositor, uint256 amount);
	event BurnCredit(address indexed burnFrom, uint256 amount, uint256 indexed forId);
	event DeductCredit(address indexed from, uint256 amount);
	
	// WARNING: the deductingContract should ALWAYS and only set the msg.sender as "address from"
	// This is the condition to be added as a deductingContract
	function deductCredit(address from, uint256 amount) external returns (bool) {
		require(deductingContract[msg.sender], "invalid sender, trusted contracts only");
		require(userCredit[from] >= amount, "insufficient voting credit");

		userCredit[from]-= amount;

		emit DeductCredit(from, amount);
		return true;
	}
	
	function addCredit() external {
		uint256 _burnedForId = IVoting(getOinkCreditContract()).burnedForId(msg.sender);
		uint256 _new = _burnedForId - addedCredit[msg.sender];
		addedCredit[msg.sender] = _burnedForId;
		userCredit[msg.sender]+=_new;
		emit AddCredit(_beneficiary, _new);
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
			setting ? ++creditingContractCount : --creditingContractCount;
			
			emit SetCreditingContract(_contract, setting);
		}
	}
	
	//add/remove contracts
	function modifyDeductingContract(address _contract, bool setting) external {
        require(msg.sender == owner(), "decentralized voting required");
		if(deductingContract[_contract] != setting) {
			deductingContract[_contract] = setting;
			setting ? ++deductingContractCount : --deductingContractCount;
			
			emit SetDeductingContract(_contract, setting);
		}
	}
	
	
	function updateChef() external {
		masterchef = IMasterChef(token.owner());
	}

	function syncOwner() external {
		_owner = token.governor();
    }

	//masterchef is the token owner, governor is the owner of masterchef
    function owner() public view returns (address) {
		return _owner;
    }

	function addressToUint256(address addr) public pure returns (uint256) {
    return uint256(uint160(addr));
}
	function getOinkCreditContract() public returns (address) {
		return IGovernor(IDTX(0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38).governor()).creditContract();
}
}
