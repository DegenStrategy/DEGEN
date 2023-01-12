// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";

import "../interface/IDTX.sol";

contract fixedSwapDTX is ReentrancyGuard {
	address public immutable DTXtoken;
	address public immutable wETH;

	uint256 public rateWETH; // amount of DTX per 1 wETH
	uint256 public ratePLS; // amount of DTX per 1 PLS


	event Swap(address sender, address sendToken, uint256 depositAmount, uint256 withdrawAmount);
    
	constructor(address _dtx, address _wETH, uint256 _rateWETH, uint256 _ratePLS) {
		DTXtoken = _dtx;
		wETH = _wETH;
		rateWETH = _rateWETH;
		ratePLS = _ratePLS;
	}

	
	function swapWETHforDTX(uint256 amount) external nonReentrant {
		address _governor = IToken(DTXtoken).governor();
		address _treasuryWallet = IGovernor(_governor).treasuryWallet();

		uint256 _toSend = getWETHinfo(amount);
		require(IERC20(wETH).transferFrom(msg.sender, _treasuryWallet, amount));
		require(IERC20(DTXtoken).transfer(msg.sender, _toSend), "transfer failed");

		emit Swap(msg.sender, wETH, amount, _toSend);
	}

	function swapPLSforDTX(uint256 amount) payable public nonReentrant {
		require(msg.value == amount);

		address _governor = IToken(DTXtoken).governor();
		address _treasuryWallet = IGovernor(_governor).treasuryWallet();

		payable(_treasuryWallet).transfer(amount);

		uint256 _toSend = getPLSInfo(amount);

		require(IERC20(DTXtoken).transfer(msg.sender, _toSend), "transfer failed");

		emit Swap(msg.sender, 0x0000000000000000000000000000000000001010, amount, _toSend);
	}

	//governing contract can cancle the sale and withdraw tokens
	//leaves possibility to withdraw any kind of token in case someone sends tokens to contract
	function withdrawTokens(uint256 amount, address _token, bool withdrawAll) external {
		address _governor = IToken(DTXtoken).governor();
		require(msg.sender == _governor, "Governor only!");
		if(withdrawAll) {
			IERC20(_token).transfer(_governor, IERC20(_token).balanceOf(address(this)));
		} else {
			IERC20(_token).transfer(_governor, amount);
		}
	}
	
	// change swap rate
	function changeSwapRate(uint256 _rateWETH, uint256 _ratePLS) external {
		address _governor = IToken(DTXtoken).governor();
		require(msg.sender == _governor, "Governor only!");
		
		rateWETH = _rateWETH;
		ratePLS = _ratePLS;
	}

	function getWETHinfo(uint256 _amount) public view returns (uint256) {
		return (_amount * rateWETH); 
	}

	function getPLSInfo(uint256 _amount) public view returns (uint256) {
		return (_amount * ratePLS); 
	}
	
}