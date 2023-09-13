// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";

// merkle-tree airdrop
// Distribution with no penalties (for contributors)
contract AirDrop is ReentrancyGuard {
	address private immutable deployer;
	IDTX public immutable DTX;

	bytes32 public merkleRoot; //root

	IMasterChef public masterchef;

    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
	
	address public votingCreditContract;
	uint256 public totalRedeemed;

	mapping(address => uint256) public amountRedeemed; // amount user already redeemed
    mapping(address => uint256) public payout; // payout for given pool

	event RedeemCredit(uint256 amount, address user, address withdrawInto);

	constructor(IDTX _dtx, IMasterChef _chef) {
		deployer = msg.sender;
		DTX = _dtx;
		masterchef = _chef;
	}

	function claimAirdrop(uint256 _claimAmount, uint256 amount, address claimInto, bytes32[] calldata merkleProof) external nonReentrant {
		require(merkleRoot != 0, "Wait until Merkle tree is provided");
		require(isValid(msg.sender, amount, merkleProof), "Merkle proof invalid");
		require(_claimAmount + amountRedeemed[msg.sender] <= amount, "insufficient credit");

		if(claimInto == acPool1 || claimInto == acPool2 || claimInto == acPool3 || claimInto == acPool4 || claimInto == acPool5 || claimInto == acPool6) {
			masterchef.publishTokens(address(this), _claimAmount);
			IacPool(claimInto).giftDeposit(_claimAmount, msg.sender, 0);
			IVoting(votingCreditContract).airdropVotingCredit(_claimAmount * payout[claimInto] / 10000, msg.sender);
		} else {
			require(claimInto == msg.sender, "invalid recipient");
			masterchef.publishTokens(msg.sender, _claimAmount);
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
	}

	function updatePools() external {
			acPool1 = IGovernor(owner()).acPool1();
			acPool2 = IGovernor(owner()).acPool2();
			acPool3 = IGovernor(owner()).acPool3();
			acPool4 = IGovernor(owner()).acPool4();
			acPool5 = IGovernor(owner()).acPool5();
			acPool6 = IGovernor(owner()).acPool6();

			votingCreditContract = IGovernor(owner()).creditContract();

			payout[acPool1] = 500;
			payout[acPool2] = 1000;
			payout[acPool3] = 1500;
			payout[acPool4] = 2000;
			payout[acPool5] = 5000;
			payout[acPool6] = 10000;	
    }

	function owner() public view returns(address) {
		return DTX.governor();
	}
}
