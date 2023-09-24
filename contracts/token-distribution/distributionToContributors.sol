// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";
import "../interface/IMasterChef.sol";

interface IDistribution {
	function setMerkle(bytes32 _merkle) external;
}

// merkle-tree airdrop
// Distribution with penalties to encourage long term participation in the protocol
contract AirDropFull is ReentrancyGuard {
	address private immutable deployer;
	IDTX public immutable DTX;

	bytes32 public merkleRoot; //root

	IMasterChef public masterchef;

    uint256 public directPayout = 8000; // 20% penalty
	uint256 public totalRedeemed;

    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
	
	address public votingCreditContract;

	address public secondDistributionContract; // second airdrop contract used for giveaways and referral rewards (has additional penalties)

	mapping(address => uint256) public amountRedeemed;
	mapping(address => uint256) public minToServe;
    mapping(address => uint256) public payout;

	event RedeemCredit(uint256 amount, address user, address withdrawInto);

	constructor(IDTX _dtx, address _secondDistributionContract) {
		deployer = msg.sender;
		DTX = _dtx;
		secondDistributionContract = _secondDistributionContract;
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

	/*
	 * Initializes merkle root in both airdrop contracts (1. to distributors and 2. to giveaways/referral rewards)
	 * Initiates minting phase in governing contract (effectively renounces contracts)
	 * Transfers credit to the second distribution contract and to address for liquidity
	*/
	function setMerkle(bytes32 _merkle, uint256 _totalCreditToContributors, bytes32 _merkleForSecondDistributionContract) external {
		require(msg.sender == deployer, "only deployer allowed!");
		require(merkleRoot == 0, "Already initialized!");
		require(_totalCreditToContributors <= 900000000 * 1e18, "Max 900M initial allocation!");
		require(_totalCreditToContributors >= 810000000 * 1e18, "Max 10% to referral and giveaways!");

		merkleRoot = _merkle;
		IGovernor(owner()).beginMintingPhase();
		masterchef.transferCredit(msg.sender, 180000000 * 1e18); // for initial liquidity
		masterchef.transferCredit(secondDistributionContract, 900000000 * 1e18 - _totalCreditToContributors); // for referral and giveaways
		IDistribution(secondDistributionContract).setMerkle(_merkleForSecondDistributionContract);
	}

	function updatePools() external {
			acPool1 = IGovernor(owner()).acPool1();
			acPool2 = IGovernor(owner()).acPool2();
			acPool3 = IGovernor(owner()).acPool3();
			acPool4 = IGovernor(owner()).acPool4();
			acPool5 = IGovernor(owner()).acPool5();
			acPool6 = IGovernor(owner()).acPool6();

			votingCreditContract = IGovernor(owner()).creditContract();
			masterchef = IMasterChef(IGovernor(owner()).masterchef());

			payout[acPool1] = 8500; // 15% penalty for 1month
			payout[acPool2] = 8750; // 12.5% penalty for 3 months
			payout[acPool3] = 9000; // 10% penalty for 6 months
			payout[acPool4] = 9500; // 5% penalty for 1year 
			payout[acPool5] = 9750; // 2.5% for 3 Year
			payout[acPool6] = 10000; // 0 penalty for 5 year
    }

	function isValid(address _user, uint256 amount, bytes32[] calldata merkleProof) public view returns(bool) {
        bytes32 node = keccak256(abi.encodePacked(_user, amount));
        return(MerkleProof.verify(merkleProof, merkleRoot, node));
    }

	function owner() public view returns(address) {
		return DTX.governor();
	}
}
