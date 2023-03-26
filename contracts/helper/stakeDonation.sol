// SPDX-License-Identifier: MIT

interface IacPool {
    function giftDeposit(
        uint256 _amount,
        address _toAddress,
        uint256 _minToServeInSecs
    ) external;
}
interface IToken {
    function balanceOf(address account) external view returns (uint256);
}
contract IssueStake {
    IToken public immutable token = IToken();
    address public immutable pool;
    address public immutable recipient;
    uint256 public immutable minServe;

    constructor(address _recipient, address _pool, uint256 _minServe) {
        recipient = _recipient;
        pool = _pool;
        minServe = _minServe;
    }

    function giftStake() external {
        IacPool(pool).giftDeposit(token.balanceOf(address(this)), recipient, minServe);
    }
}
