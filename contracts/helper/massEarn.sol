// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

interface IVault {
	function startEarningFromPulseX(address _referral, bool isProxy) external;
	function stakeHexShares(address _referral, bool isProxy) external;
}

// start earning from multiple vaults in a single transaction
contract massEarn {
  address public immutable hexSharesVault;
  address public immutable pulseXVaultPLSX;
  address public immutable pulseXVaultPLS;
  address public immutable pulseXVaultHEX;
  address public immutable pulseXVaultINC;

  constructor(address _hexVault, address _plsx, address _pls, address _hexTokenVault, address _inc) {
	hexSharesVault = _hexVault;
	pulseXVaultPLSX = _plsx;
	pulseXVaultPLS = _pls;
	pulseXVaultHEX = _hexTokenVault;
	pulseXVaultINC = _inc;
  }
  
  function startEarning(address _referral, bool _hexVault, bool _plsx, bool _pls, bool _hexToken, bool _inc) external {
	if(_hexVault) { IVault(hexSharesVault).stakeHexShares(_referral, true); }
	
	if(_plsx) { IVault(pulseXVaultPLSX).startEarningFromPulseX(_referral, true); }
	
	if(_pls) { IVault(pulseXVaultPLS).startEarningFromPulseX(_referral, true); }
	
	if(_hexToken) { IVault(pulseXVaultHEX).startEarningFromPulseX(_referral, true); }
	
	if(_inc) { IVault(pulseXVaultINC).startEarningFromPulseX(_referral, true); }
  }
}
