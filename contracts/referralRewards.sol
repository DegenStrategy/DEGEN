// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IVault.sol";
import "./interface/IacPool.sol";

contract RedeemReferralRewards {
	address public immutable token;
	mapping(address => uint256) public amountRedeemed;
	
	event ClaimReferralReward(address indexed user, address claimInto, uint256 amount);
	
	constructor (address _token) {
		token = _token;
	}
	
	function redeemRewards(uint256 _amount, address _into) external {
		uint256 _available = totalUserRewards(msg.sender) - amountRedeemed[msg.sender];
		require(_available >= _amount, "insufficient rewards available!");
		
		amountRedeemed[msg.sender]+= _amount;

		uint256 _poolPayout = IVault(IGovernor(governor()).plsVault()).viewPoolPayout(_into);
		uint256 _payout = 0;
		
		uint256 referralBonus = IGovernor(governor()).referralBonus();
		
		_amount = _amount * referralBonus / 10000;
			
		uint256 _minServe = 0;
		
		if(_poolPayout == 0) { //send into wallet
			_payout = _amount * IVault(IGovernor(governor()).plsVault()).defaultDirectPayout() / 10000;
			
			require(IDTX(token).balanceOf(address(this)) >= _payout, "The reward contract has insufficient balance!");
			IDTX(token).transfer(_into, _payout);
		} else {							
			_payout = _amount * _poolPayout / 10000; 
			require(IDTX(token).balanceOf(address(this)) >= _payout, "The reward contract has insufficient balance!");
			_minServe = IVault(IGovernor(governor()).plsVault()).viewPoolMinServe(_into);
			IacPool(_into).giftDeposit(_payout, msg.sender, _minServe);
		}

		emit ClaimReferralReward(msg.sender, _into, _payout);
	}
	

	
	function totalUserRewards(address _user) public view returns (uint256) {
		address _governor = governor();
		uint256 _vault1 = IVault(IGovernor(_governor).plsVault()).referralPoints(_user);
		uint256 _vault2 = IVault(IGovernor(_governor).plsxVault()).referralPoints(_user);
		uint256 _vault3 = IVault(IGovernor(_governor).incVault()).referralPoints(_user);
		uint256 _vault4 = IVault(IGovernor(_governor).hexVault()).referralPoints(_user);
		uint256 _vault5 = IVault(IGovernor(_governor).tshareVault()).referralPoints(_user);
		
		return (_vault1 + _vault2 + _vault3 + _vault4 + _vault5);
	}
	
	function governor() public view returns (address) {
		return IDTX(token).governor();
	}
}
