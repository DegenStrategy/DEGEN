// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../interface/IDTX.sol";
import "../interface/IGovernor.sol";

contract TokenBalancer {
    IUniswapV2Router02 public immutable uniswapRouter;
    address public immutable token1 = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab; //pls
    address public immutable token2 = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d; //inc
    address public immutable farmer;
    address public immutable DTX = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    
    constructor(
        address _farmer
    ) {
        uniswapRouter = IUniswapV2Router02(0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02);
        farmer = _farmer;
    }
    
    function sendToFarmer(address _token) external {
        require(_token != token1 || _token != token2, "not this token");
        IERC20(_token).transfer(farmer, IERC20(_token).balanceOf(address(this)));
    }

    function getRelativeValue(address baseToken, address quoteToken, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        
        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = quoteToken;
        
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amount, path);
        return amountsOut[1];
    }
    
    function calculateOptimalSwap() public view returns (
        uint256 token1Value,
        uint256 token2Value,
        bool shouldSwapToken1,
        uint256 amountToSwap
    ) {
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));
        uint256 token2Balance = IERC20(token2).balanceOf(address(this));
        
        // Get value of token1 in terms of token2
        token1Value = getRelativeValue(token1, token2, token1Balance);
        token2Value = token2Balance; // We use token2 as the quote currency
        
        if (token1Value > token2Value) {
            shouldSwapToken1 = true;
            // Calculate how much token1 to swap to match token2's value
            uint256 excessValue = token1Value - token2Value;
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = token2;
            uint256[] memory amounts = uniswapRouter.getAmountsIn(excessValue / 2, path);
            amountToSwap = amounts[0];
        } else {
            shouldSwapToken1 = false;
            // Calculate how much token2 to swap to match token1's value
            uint256 excessValue = token2Value - token1Value;
            address[] memory path = new address[](2);
            path[0] = token2;
            path[1] = token1;
            uint256[] memory amounts = uniswapRouter.getAmountsIn(excessValue / 2, path);
            amountToSwap = amounts[0];
        }
    }
    
    function balanceAndProvideLiquidity() external {
        // Calculate optimal swap between token1 and token2
        (,, bool shouldSwapToken1, uint256 amountToSwap) = calculateOptimalSwap();
        
        // Perform the swap to balance values
        if (amountToSwap > 0) {
            address tokenIn = shouldSwapToken1 ? token1 : token2;
            address tokenOut = shouldSwapToken1 ? token2 : token1;
            
            IERC20(tokenIn).approve(address(uniswapRouter), amountToSwap);
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            uniswapRouter.swapExactTokensForTokens(
                amountToSwap,
                0, // Accept any amount of tokens
                path,
                address(this),
                block.timestamp
            );
        }
        
        // Add liquidity
        uint256 token1Balance = IERC20(token1).balanceOf(address(this));
        uint256 token2Balance = IERC20(token2).balanceOf(address(this));
        
        IERC20(token1).approve(address(uniswapRouter), token1Balance);
        IERC20(token2).approve(address(uniswapRouter), token2Balance);
        
        uniswapRouter.addLiquidity(
            token1,
            token2,
            token1Balance,
            token2Balance,
            0, // Accept any amount of token1
            0, // Accept any amount of token2
            address(this),
            block.timestamp
        );
    }
    
    // Function to handle received LP tokens
    function getLPTokenAddress() public view returns (address) {
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        return factory.getPair(token1, token2);
    }

    function governor() public view returns (address) {
        return IDTX(DTX).governor();
    }

    function treasury() public view returns (address) {
        return IGovernor(governor()).treasuryWallet();
    }

    //in case tokens get stuck
    function emergencyWithdraw(address _token) external {
        require(msg.sender == governor(), "governor contract only");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }
}
