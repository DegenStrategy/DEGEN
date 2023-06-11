pragma solidity ^0.8.0;
//SPDX-License-Identifier: NONE

import "../interface/IDTX.sol";

interface IHex {
    function stakeStart(uint256 newStakedHearts, uint256 newStakedDays) external;
    function stakeLists(address, uint256) external view returns (uint40, uint72, uint72, uint16, uint16, uint16, bool);
    function stakeEnd(uint256 stakeIndex, uint40 stakeIdParam) external;
    function balanceOf(address account) external view returns (uint256);
    function currentDay()
        external
        view
        returns (uint256)
    {
        return _currentDay();
    }
    function transfer(address recipient, uint256 amount) external returns (bool);
}


contract HexBurnAndStake {
  IHex public immutable hex = IHex(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39);
  address public immutable ourToken;
  
  constructor(address _XPD) {
   ourToken = _XPD;
  }
  
  function stake() external {
    hex.stakeStart(hex.balanceOf(address(this)), 5555); //burns HEX and stakes full balance for 5555 days
  }
  
  function endStake(uint256 stakeId) external {
    (uint40 stakeListId, , , uint256 enterDay , , ,) = hex.stakeLists(address(this), stakeId);
    
    require(enterDay + 5555 <= hex.currentDay(), "Must serve full term of 5555 days");
    
    hex.stakeEnd(stakeId, stakeListId);
    
    hex.transfer(IDTX(ourToken).governor(), hex.balanceOf(address(this)));
  }
}
