// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

contract NftAllocationSpecific {
	address public constant landNftContract = ;
	
	uint256 public baseAllocation = 25000000*1e18;
	
	function nftAllocation(address _tokenAddress, uint256 _tokenID) external view returns (uint256) {
		require(_tokenAddress == landNftContract, "invalid token");
			uint256 _value = baseAllocation;
		for(uint i=0; i< _tokenID; i++) {
			_value = _value * 996 / 1000;
		}
		return _value;
	}
	
	//for testnet only
	function setBaseAllocation(uint256 _amount) external {
		require(msg.sender == 0xbc1D954E7a52C7acb2D28C951f305D73722C5c0D, "admin only");
		baseAllocation = _amount;
	}
}
