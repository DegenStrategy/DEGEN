// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";


import "./interface/IDTX.sol";
import "./interface/IGovernor.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

interface IVault {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);
}

contract DegenSwapper {
	address public constant UNISWAP_ROUTER_ADDRESS = 0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02;
    address public constant OINK = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public constant WPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
	address public constant DEGEN = ;
	address public  authorizedAddress;
	address public constant WETH_ADDRESS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    bool public allowAll = true;

    IUniswapV2Router02 public constant uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);

    mapping(address => bool) public exoticToken;
    mapping(address => bool) public exoticTokenPath;
    mapping(address => bool) public  allowedPhux;
    mapping(bytes32 => bool) public allowedPhuxId;

    // Balancer V2 Vault address (mainnet)
    IVault public constant vault = IVault(0x7F51AC3df6A034273FB09BB29e383FCF655e473c);

	

    constructor() {
		authorizedAddress = msg.sender;
        allowedPhux[0x6C203A555824ec90a215f37916cf8Db58EBe2fA3] = true; // print
        allowedPhuxId[0x30dd5508c3b1deb46a69fe29955428bb4e0733d90001000000000000000004b6] = true; // INC

        allowedPhux[0x9663c2d75ffd5F4017310405fCe61720aF45B829] = true; // phux and 2phux
        allowedPhux[0x115f3Fa979a936167f9D208a7B7c4d85081e84BD] = true;

        allowedPhuxId[0x7b70f6c77f7e3effe28495dbbd146f9a8af1afe50001000000000000000003cc] = true; // 2phux -> wpls
        allowedPhuxId[0x545998abcbf0633c83ba20cb94f384925be75dd5000200000000000000000000] = true; // phux -> wpls

        //approval for wpls, PRINT, inc, hex, plsx
        IERC20(WPLS).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x95B303987A60C71504D99Aa1b13B4DA07b0790ab).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
    }

    event BoughtOink(uint256 amountSpent, uint256 amountReceived);
	
	modifier onlyAuthorized() {
        if(!allowAll) {
            require(msg.sender == authorizedAddress, "authorized address only");        
        }
        _;
	}
	
    function buyOink(uint256 _swapAmount) public onlyAuthorized {
        uint deadline = block.timestamp + 15; 

        uint[] memory amountsOut = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath());
        uint minOut = (amountsOut[amountsOut.length-1] * 97) / 100; // 3% slippage tolerance
        
        uniswapRouter.swapExactTokensForTokens(
            _swapAmount,      // amountIn
            minOut,           // amountOutMin
            getTokenPath(), 
            treasury(), 
            deadline
        );

        emit BoughtOink(_swapAmount, IERC20(OINK).balanceOf(address(this)));
    }

    function buyOinkFixed(uint256 _swapAmount, uint256 _minOut) public onlyAuthorized {
        uint deadline = block.timestamp + 15; 
        
        uniswapRouter.swapExactTokensForTokens(
            _swapAmount,      // amountIn
            _minOut,          // amountOutMin (caller provides this)
            getTokenPath(), 
            treasury(), 
            deadline
        );

        emit BoughtOink(_swapAmount, IERC20(OINK).balanceOf(address(this)));
    }

    function swapForWpls(uint256 _swapAmount, address _token, uint256 _minOut) public onlyAuthorized {
        require(_token != OINK && _token != WPLS && _token != DEGEN, "not allowed for these tokens");
        uint deadline = block.timestamp + 15; 

        uniswapRouter.swapExactTokensForTokens(
            _swapAmount,      // amountIn
            _minOut,          // amountOutMin
            getTokenPath2(_token), 
            address(this), 
            deadline
        );
    }


    function swapExoticTokenForWPLS(address _token, address _into) external onlyAuthorized {
        require(exoticToken[_token], "submitted exotic token is not enabled");
        require(exoticTokenPath[_into], "submitted exotic token path is not enabled");

        uint deadline = block.timestamp + 15; 
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = _token;
        path[1] = _into;
        path[2] = WPLS;

        // Get expected output amounts
        uint[] memory amountsOut = uniswapRouter.getAmountsOut(tokenBalance, path);
        
        // Apply slippage tolerance (e.g., 3% slippage)
        uint256 minAmountOut = amountsOut[amountsOut.length - 1] ;

        // Use swapExactTokensForTokens instead
        uniswapRouter.swapExactTokensForTokens(
            tokenBalance,      // amountIn
            minAmountOut,      // amountOutMin  
            path,              // path
            address(this),     // to
            deadline           // deadline
        );
    }


    //swap on phux
    function swapOnPhuxForWPLS(
        address tokenIn, // Address of the input token (e.g., DAI)
        bytes32 poolId // Balancer pool ID (e.g., DAI/WETH pool)
    ) external onlyAuthorized {
        require(allowedPhux[tokenIn], "token is not enabled");
        require(allowedPhuxId[poolId], "phux pool is not enabled");
        uint256 deadline = block.timestamp + 15;
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));


        IERC20(tokenIn).approve(address(vault), amountIn);

        // Define the swap parameters
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind.GIVEN_IN, // Specify exact amount in
            assetIn: tokenIn,
            assetOut: WPLS,
            amount: amountIn,
            userData: "0x" // No additional data needed for standard swaps
        });

        // Define fund management parameters
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this), // This contract sends the tokens
            fromInternalBalance: false, // Use external balance
            recipient: payable(address(this)), // Send WETH to the caller
            toInternalBalance: false // Do not use internal balance
        });

        // Execute the swap with no minimum amount out (ignoring slippage)
        // small amount of rewards from constant rewards so no care for slippage
        uint256 amountOut = vault.swap(singleSwap, funds, 0, deadline);
    }

	function enableToken(address _token) external {
        IERC20(_token).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
    }

	function getTokenPath() private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WPLS;
        path[1] = OINK;
        return path;
    }

	 function getTokenPath2(address _token) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = WPLS;
        return path;
    }

	function getMinOut(uint256 _swapAmount, address[] memory _path) external view returns (uint256) {
	    uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, _path);
        uint _minOut = _minOutT[_minOutT.length-1];
	    return _minOut;
    }

    function wrapPls() external {
        uint256 amount = address(this).balance;
        require(amount > 0, "No PLS balance");
        
        // Get WETH contract
        IWETH weth = IWETH(WETH_ADDRESS);
        
        // Wrap ETH to WETH
        weth.deposit{value: amount}();
    }

    function withdraw(address _token) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }
    
    function sendToTreasury(address _token, uint256 _amount) external  {
      require(msg.sender == governor() || msg.sender == authorizedAddress, "only thru decentralized Governance");
	  IERC20(_token).transfer(treasury(), _amount);
    }

	function recoverETH() external {
        require(msg.sender == governor() || msg.sender == authorizedAddress, "governor only");
        address payable recipient = payable(treasury());
        recipient.transfer(address(this).balance);
    }

    function recoverToken(address _token) external {
        require(msg.sender == governor(), "governor only");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }

	function modifyAuthorized(address _newAddress) external  {
		require(msg.sender == authorizedAddress, "authorized address only");
        authorizedAddress = _newAddress;
	}

    function modifyAllowAll(bool _setting) external  {
		require(msg.sender == authorizedAddress, "authorized address only");
        allowAll = _setting;
	}

    function modifyExotic(address _token, bool _setting) external {
		require(msg.sender == authorizedAddress, "authorized address only");
        exoticToken[_token] = _setting;
	}
    function modifyExoticPath(address _token, bool _setting) external {
		require(msg.sender == authorizedAddress, "authorized address only");
        exoticTokenPath[_token] = _setting;
	}
    function modifyPhux(address _token, bool _setting) external {
		require(msg.sender == authorizedAddress, "authorized address only");
        allowedPhux[_token] = _setting;
	}
    function modifyPhuxPool(bytes32 _poolId, bool _setting) external {
		require(msg.sender == authorizedAddress, "authorized address only");
        allowedPhuxId[_poolId] = _setting;
	}

	function governor() public view returns (address) {
		return IDTX(OINK).governor();
	}

  	function treasury() public view returns (address) {
		return IGovernor(governor()).treasuryWallet();
	}

	// Simple ETH receiver functions
    receive() external payable {}
    fallback() external payable {}
}
