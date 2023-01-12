pragma solidity ^0.8.0;
//SPDX-License-Identifier: NONE

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IDTX.sol";

contract DTXtreasury {
  address public immutable token; // DTX token(address)

  /// @notice Event emitted when new transaction is executed
  event ExecuteTransaction(address indexed token, address indexed recipientAddress, uint256 value);

  constructor(address _DTX) {
   token = _DTX;
  }
  
   modifier onlyOwner() {
    require(msg.sender == IDTX(token).governor(), "admin: wut?");
    _;
   }

  /**
   * Initiate withdrawal from treasury wallet
   */
  function requestWithdraw(address _token, address _receiver, uint _value) external onlyOwner {
    // If token address is 0x0, transfer native tokens
    if (_token == address(0) || _token == 0x0000000000000000000000000000000000001010) payable(_receiver).transfer(_value);
    // Otherwise, transfer ERC20 tokens
    else IERC20(_token).transfer(_receiver, _value);

    emit ExecuteTransaction(_token, _receiver, _value);
  }

  /// @notice Fallback functions to receive native tokens
  receive() external payable { } 
  fallback() external payable { }
}
