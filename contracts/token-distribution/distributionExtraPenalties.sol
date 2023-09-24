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

// merkle-tree airdrop
// Distribution with penalties (for referrals, locked(illiquid) contributions, rewards(giveaways))
contract AirDropLockExtra is ReentrancyGuard {
	address private immutable deployer;
	uint256 public constant CLAIM_PERIOD_DAYS = 180;

	IDTX public immutable DTX;

	bytes32 public merkleRoot; //root

	IMasterChef public masterchef;

    uint256 public startTime;
    uint256 public directPayout = 250; // 97.5% penalty
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

	constructor(IDTX _dtx) {
		deployer = msg.sender;
		DTX = _dtx;
		startTime = block.timestamp;
	}

	function claimAirdrop(uint256 _claimAmount, uint256 amount, address claimInto, bytes32[] calldata merkleProof) external nonReentrant {
		require(merkleRoot != 0, "Wait until Merkle tree is provided");
		require(isValid(msg.sender, amount, merkleProof), "Merkle proof invalid");
		require(_claimAmount + amountRedeemed[msg.sender] <= amount, "insufficient credit");

		if(claimInto == acPool1 || claimInto == acPool2 || claimInto == acPool3 || claimInto == acPool4 || claimInto == acPool5 || claimInto == acPool6) {
			masterchef.publishTokens(address(this), _claimAmount * payout[claimInto] / 10000);
			IacPool(claimInto).giftDeposit((_claimAmount * payout[claimInto] / 10000), msg.sender, minToServe[claimInto]);
			IVoting(votingCreditContract).airdropVotingCredit(_claimAmount * payout[claimInto] / 10000, msg.sender);
		} else {
			require(claimInto == msg.sender, "invalid recipient");
			masterchef.publishTokens(msg.sender, (_claimAmount * directPayout / 10000));
		}

		amountRedeemed[msg.sender]+= _claimAmount;
		totalRedeemed+= _claimAmount;

		emit RedeemCredit(_claimAmount, msg.sender, claimInto);
	}

    // ends the airdrop by emptying token balance(sends tokens to governing contract)
	function endAirdrop() external {
		require(block.timestamp > startTime + CLAIM_PERIOD_DAYS * 86400, "airdrop still active");
		masterchef.publishTokens(owner(), masterchef.credit(address(this)));
	}

	function setMerkle(bytes32 _merkle) external {
		require(tx.origin == deployer, "only deployer allowed!");
		require(merkleRoot == 0, "Already initialized!");
		merkleRoot = _merkle;
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

			minToServe[acPool1] = 864000;
			minToServe[acPool2] = 2592000;
			minToServe[acPool3] = 5184000;
			minToServe[acPool4] = 8640000;
			minToServe[acPool5] = 20736000;
			minToServe[acPool6] = 31536000;

			payout[acPool1] = 500;
			payout[acPool2] = 1000;
			payout[acPool3] = 1500;
			payout[acPool4] = 2000;
			payout[acPool5] = 5000;
			payout[acPool6] = 10000;	
    }

	function isValid(address _user, uint256 amount, bytes32[] calldata merkleProof) public view returns(bool) {
        bytes32 node = keccak256(abi.encodePacked(_user, amount));
        return(MerkleProof.verify(merkleProof, merkleRoot, node));
    }

	function owner() public view returns(address) {
		return DTX.governor();
	}
}
