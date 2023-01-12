// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface ITreasury {
    event ExecuteTransaction(
        address indexed token,
        address indexed recipientAddress,
        uint256 value
    );

    fallback() external payable;

    function requestWithdraw(
        address _token,
        address _receiver,
        uint256 _value
    ) external;

    function token() external view returns (address);

    receive() external payable;
}