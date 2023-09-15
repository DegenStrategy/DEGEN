// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";

// merkle-tree airdrop
// Distribution with penalties to encourage long term participation in the protocol
contract AirDrop is ReentrancyGuard {
	address private immutable deployer;
	IDTX public immutable DTX;

	bytes32 public merkleRoot; //root

	IMasterChef public masterchef;

    uint256 public startTime;
    uint256 public directPayout = 8000; // 20% penalty
	uint256 public totalRedeemed;

    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
	
	address public votingCreditContract;

	mapping(address => uint256) public amountRedeemed;
	mapping(address => uint256) public minToServe;
    mapping(address => uint256) public payout;

	event RedeemCredit(uint256 amount, address user, address withdrawInto);

	constructor(IDTX _dtx, IMasterChef _chef) {
		deployer = msg.sender;
		DTX = _dtx;
		startTime = block.timestamp;
		masterchef = _chef;
	}

	function claimAirdrop(uint256 _claimAmount, uint256 amount, address claimInto, bytes32[] calldata merkleProof) external nonReentrant {
		require(merkleRoot != 0, "Wait until Merkle tree is provided");
		require(isValid(msg.sender, amount, merkleProof), "Merkle proof invalid");
		require(_claimAmount + amountRedeemed[msg.sender] <= amount, "insufficient credit");

		uint256 _penalty;
		uint256 _reward;

		if(claimInto == acPool1 || claimInto == acPool2 || claimInto == acPool3 || claimInto == acPool4 || claimInto == acPool5 || claimInto == acPool6) {
			_reward = _claimAmount * payout[claimInto] / 10000;
			_penalty = _claimAmount - _reward;

			masterchef.publishTokens(address(this), _reward);
			IacPool(claimInto).giftDeposit(_reward, msg.sender, 0);
			IVoting(votingCreditContract).airdropVotingCredit(_reward, msg.sender);

			masterchef.publishTokens(owner(), _penalty);
		} else {
			require(claimInto == msg.sender, "invalid recipient");

			_reward = _claimAmount * directPayout / 10000;
			_penalty = _claimAmount - _reward;

			masterchef.publishTokens(msg.sender, _reward);
			masterchef.publishTokens(owner(), _penalty);
		}

		amountRedeemed[msg.sender]+= _claimAmount;
		totalRedeemed+= _claimAmount;

		emit RedeemCredit(_claimAmount, msg.sender, claimInto);
	}


	function isValid(address _user, uint256 amount, bytes32[] calldata merkleProof) public view returns(bool) {
        bytes32 node = keccak256(abi.encodePacked(_user, amount));
        return(MerkleProof.verify(merkleProof, merkleRoot, node));
    }

	function setMerkle(bytes32 _merkle) external {
		require(msg.sender == deployer, "only deployer allowed!");
		require(merkleRoot == 0, "Already initialized!");
		merkleRoot = _merkle;
		IGovernor(owner()).beginMintingPhase();
	}

	function updatePools() external {
			acPool1 = IGovernor(owner()).acPool1();
			acPool2 = IGovernor(owner()).acPool2();
			acPool3 = IGovernor(owner()).acPool3();
			acPool4 = IGovernor(owner()).acPool4();
			acPool5 = IGovernor(owner()).acPool5();
			acPool6 = IGovernor(owner()).acPool6();

			votingCreditContract = IGovernor(owner()).creditContract();

			payout[acPool1] = 8500; // 15% penalty for 1month
			payout[acPool2] = 8750; // 12.5% penalty for 3 months
			payout[acPool3] = 9000; // 10% penalty for 6 months
			payout[acPool4] = 9500; // 5% penalty for 1year 
			payout[acPool5] = 9750; // 2.5% for 3 Year
			payout[acPool6] = 10000; // 0 penalty for 5 year
    }

	function owner() public view returns(address) {
		return DTX.governor();
	}
}
