// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IGovernor.sol";
import "./interface/IDTX.sol";
import "./interface/IVault.sol";
import "./interface/IacPool.sol";
import "./interface/IMasterChef.sol";

contract RedeemReferralRewards {
	address public immutable token;
	address private _governor;
	mapping(address => uint256) public amountRedeemed;

	address[] public vaults;
	
	event ClaimReferralReward(address indexed user, address claimInto, uint256 amount);
	
	constructor (
		address _token,
		address _plsVault,
		address _plsxVault,
		address _incVault,
		address _hexVault,
		address _tshareVault
	) {
		token = _token;
		vaults.push(_plsVault);
		vaults.push(_plsxVault);
		vaults.push(_incVault);
		vaults.push(_hexVault);
		vaults.push(_tshareVault);
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

	// If new pool is added in MasterChef, must manually add it to view referral points
	// Caution when adding new pool, so that .referralPoints(user) returns proper amount!
	function addVault(uint256 _poolId) external {
		address _masterchef = IGovernor(_governor).masterchef();

		( , , address _vault) = IMasterChef(_masterchef).poolInfo(_poolId);

		for(uint256 i=0; i < vaults.length; i++) {
			require(_vault != vaults[i], "Vault already exists!");
		}
	
		uint256 _checkIfReturns = IVault(_vault).referralPoints(address(this)); // will revert if vault syntax does not match
		vaults.push(_vault);
	}
	
	function syncOwner() external {
		_governor = IDTX(token).governor();
	}

	function withdrawTokens(uint256 _amount) external {
		require(msg.sender == governor(), "decentralized voting only");
		IERC20(token).transfer(governor(), _amount);
	}

	function totalUserRewards(address _user) public view returns (uint256) {
		address _governor = governor();
		uint256 _total = 0;

		for(uint256 i=0; i < vaults.length; i++) {
			_total+= IVault(vaults[i]).referralPoints(_user);
		}

		return _total;
	}

	function governor() public view returns (address) {
		return _governor;
	}
}
