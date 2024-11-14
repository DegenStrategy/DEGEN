// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";

import "../interface/IDTX.sol";
import "../interface/IGovernor.sol";

contract AccumulateDTX {
	uint256 public constant MAX_SWAP = 100000000 * 1e18;
    address public constant UNISWAP_ROUTER_ADDRESS = 0x165C3410fC91EF562C50559f7d2289fEbed552d9;
    address public immutable DTX = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public immutable wPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;

    IUniswapV2Router02 public uniswapRouter;

    constructor() {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
		IERC20(0xA1077a294dDE1B09bB078844df40758a5D0f9a27).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
		IERC20(0x95B303987A60C71504D99Aa1b13B4DA07b0790ab).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
		IERC20(0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
		IERC20(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
    }

    function buyWithPLS() public {
		require(msg.sender == tx.origin);
        uint deadline = block.timestamp + 15; 
		uint256 _swapAmount = address(this).balance;
		if(_swapAmount > MAX_SWAP) { _swapAmount = MAX_SWAP; }
        uint[] memory _minOutT = getEstimatedDTXforETH();
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapETHForExactTokens{ value: _swapAmount }(_minOut, getPLSpath(), address(this), deadline);
		IERC20(DTX).transfer(treasury(), IERC20(DTX).balanceOf(address(this)));
    }
	
	function swapTokenForPLS(address _token, uint256 _amount) external {
		require(msg.sender == tx.origin);
        uint deadline = block.timestamp + 15; 
		uint256 _swapAmount = IERC20(_token).balanceOf(address(this));
        uint[] memory _minOutT = getEstimatedPLSforToken(_token);
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        uniswapRouter.swapTokensForExactETH(_minOut, _swapAmount, getTokenPath(_token), address(this), deadline);
	}

    function withdraw() external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        payable(treasury()).transfer(address(this).balance);
    }
	
	function withdrawToken(address _a) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        require(IERC20(_a).transfer(treasury(), IERC20(_a).balanceOf(address(this))));
    }
	
	function enableToken(address _token) external {
		IERC20(_token).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
	}
    

    //with gets amount in you provide how much you want out
    function getEstimatedDTXforETH() public view returns (uint[] memory) {
		uint256 _swapAmount = address(this).balance;
		if(_swapAmount > MAX_SWAP) { _swapAmount = MAX_SWAP; }
        return uniswapRouter.getAmountsOut(_swapAmount, getPLSpath()); //NOTICE: ETH is matic PLS
    }
	
	function getEstimatedPLSforToken(address _token) public view returns (uint[] memory) {
        return uniswapRouter.getAmountsOut(IERC20(_token).balanceOf(address(this)), getTokenPath(_token)); 
    }
	
    function getPLSpath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = wPLS;
        path[1] = DTX;

        return path;
    }
	
	function getTokenPath(address _token) private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = wPLS;

        return path;
    }

	function governor() public view returns (address) {
		return IDTX(DTX).governor();
	}

  	function treasury() public view returns (address) {
		return IGovernor(governor()).treasuryWallet();
	}

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
