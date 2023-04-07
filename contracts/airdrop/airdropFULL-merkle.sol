// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";

contract AirDrop is ReentrancyGuard {
  bytes32 public merkleRoot =; //root
	IDTX public immutable DTX;

	uint256 public totalCredit;

    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
	
	address public votingCreditContract;

	mapping(address => uint256) public amountRedeemed;

	event AddCredit(uint256 credit, address user);

	constructor(IDTX _dtx) {
		DTX = _dtx;
	}

	function claimAirdrop(uint256 _claimAmount, uint256 amount, address claimInto, bytes32[] calldata merkleProof) external nonReentrant {
		require(isValid(msg.sender, amount, merkleProof), "proof invalid");
        require(_claimAmount + amountRedeemed[msg.sender] <= amount, "insufficient credit");
		if(claimInto == acPool1 || claimInto == acPool2 || claimInto == acPool3 || claimInto == acPool4 || claimInto == acPool5 || claimInto == acPool6) {
			IacPool(claimInto).giftDeposit(_claimAmount, msg.sender, 0);
			IVoting(votingCreditContract).airdropVotingCredit(_claimAmount * payout[claimInto] / 1000, msg.sender);
		} else {
			require(DTX.transfer(msg.sender, _claimAmount));
		}

		amountRedeemed[msg.sender]+= _claimAmount;

		emit RedeemCredit(_claimAmount, msg.sender, claimInto);
	}
  
    function isValid(address _user, uint256 amount, bytes32[] calldata merkleProof) public view returns(bool) {
        bytes32 node = keccak256(abi.encodePacked(_user, amount));
        return(MerkleProof.verify(merkleProof, merkleRoot, node));
    }

	function updatePools() external {
			acPool1 = IGovernor(owner()).acPool1();
			acPool2 = IGovernor(owner()).acPool2();
			acPool3 = IGovernor(owner()).acPool3();
			acPool4 = IGovernor(owner()).acPool4();
			acPool5 = IGovernor(owner()).acPool5();
			acPool6 = IGovernor(owner()).acPool6();
			
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
