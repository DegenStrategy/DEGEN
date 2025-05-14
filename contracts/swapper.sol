// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";

import "../interface/IDTX.sol";
import "../interface/IGovernor.sol";

contract DegenSwapper {
	address public constant UNISWAP_ROUTER_ADDRESS = ;
    address public constant OINK = ;
    address public constant wPLS = ;
	address public constant DEGEN = ;
	address public immutable authorizedAddress;

    IUniswapV2Router02 public constant uniswapRouter = IUniswapV2Router02();
	

    constructor() {
		authorizedAddress = msg.sender;
    }
	
	modifier onlyAuthorized() {
		require(msg.sender == authorizedAddress, "authorized address only");
		_;
	}

	function sellDegen(uint256 _swapAmount) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 

        uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath());
        uint _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath(), address(this), deadline);
    }
	
	
	function buyOink(uint256 _swapAmount) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 

        uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath2());
        uint _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath2(), address(this), deadline);
    }
	
	function sellDegenBuyOink(uint256 _swapAmount) public onlyAuthorized {
		uint deadline = block.timestamp + 15; 

        uint[] memory _minOutT = uniswapRouter.getAmountsOut(_swapAmount, getTokenPath());
        uint _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath(), address(this), deadline);
		
		_minOutT = uniswapRouter.getAmountsOut(_minOut, getTokenPath3());
        _minOut = _minOutT[_minOutT.length-1];
        uniswapRouter.swapTokensForExactTokens(_minOut, _swapAmount, getTokenPath2(), address(this), deadline);
    }
	


    function withdraw(address _token) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }
    
    function sendToTreasury(address _token, uint256 _amount) external onlyAuthorized {
      require(msg.sender == governor(), "only thru decentralized Governance");
	  IERC20(_token).transfer(treasury(), _amount);
    }


	function enableToken(address _token) external {
        IERC20(_token).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
    }
    
    function getTokenPath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = DEGEN;
        path[1] = WPLS;
        return path;
    }
	
	function getTokenPath2() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WPLS;
        path[1] = OINK;
        return path;
    }
	
	function modifyAuthorized(address _newAddress) external onlyAuthorized {
		authorizedAddress = _newAddress;
	}

	function governor() public view returns (address) {
		return IDTX(OINK).governor();
	}

  	function treasury() public view returns (address) {
		return IGovernor(governor()).treasuryWallet();
	}
}
