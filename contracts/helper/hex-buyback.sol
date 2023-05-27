// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router02 {
    function WPLS() external pure returns (address);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}


contract BuybackHEX {
    address public constant UNISWAP_ROUTER_ADDRESS = 0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02;
    address public constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;

    IUniswapV2Router02 public pulsexRouter;

    address[] public path;

    constructor() {
        pulsexRouter = IUniswapV2Router02(0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02);
        path = new address[](2);
        path[0] = pulsexRouter.WPLS();
        path[1] = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    }

    function buyBackHexNBurn() public {
    	require(msg.sender == tx.origin);
        uint deadline = block.timestamp + 15; 
        uint[] memory _minOutT = pulsexRouter.getAmountsOut(address(this).balance, path);
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        pulsexRouter.swapETHForExactTokens{ value: address(this).balance }(_minOut, path, address(this), deadline);
        IERC20(HEX).transfer(address(HEX), IERC20(HEX).balanceOf(address(this))); //equivalent to burn
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
