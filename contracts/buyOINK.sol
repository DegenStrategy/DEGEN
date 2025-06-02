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

contract DegenSwapper {
	address public constant UNISWAP_ROUTER_ADDRESS = 0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02;
    address public constant OINK = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public constant WPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
	address public constant DEGEN = ;
	address public  authorizedAddress;
	address public constant WETH_ADDRESS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    bool public allowAll = true;

    IUniswapV2Router02 public constant uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
	

    constructor() {
		authorizedAddress = msg.sender;
    }
	
	modifier onlyAuthorized() {
        if(!allowAll) {
            require(msg.sender == authorizedAddress, "authorized address only");
                    
        }
        _;
	}
	
	function buyOink(uint256 _swapAmount) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 

        uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath());
        uint _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath(), address(this), deadline);

	IERC20(OINK).transfer(treasury(), IERC20(OINK).balanceOf(address(this)));
    }

	function buyOinkFixed(uint256 _swapAmount, uint256 _minOut) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath(), address(this), deadline);

	IERC20(OINK).transfer(treasury(), IERC20(OINK).balanceOf(address(this)));
    }


    function withdraw(address _token) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }
    
    function sendToTreasury(address _token, uint256 _amount) external  {
      require(msg.sender == governor() || msg.sender == authorizedAddress, "only thru decentralized Governance");
	  IERC20(_token).transfer(treasury(), _amount);
    }


	function swapForWpls(uint256 _swapAmount, address _token) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 

        uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath2(_token));
        uint _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath2(_token), address(this), deadline);
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

	function getMinOut(uint256 _swapAmount) external view returns (uint256) {
	uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath());
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
