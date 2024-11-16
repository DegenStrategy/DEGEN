// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "../interface/IDTX.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";

contract AccumulateDTX {
    uint256 public constant MAX_SWAP = 100000000 * 1e18;
    uint256 public constant MAX_DAILY_PERCENT = 5; // 5% daily limit
    address public constant UNISWAP_ROUTER_ADDRESS = 0x165C3410fC91EF562C50559f7d2289fEbed552d9;
    address public immutable DTX = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public immutable wPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public immutable votingCreditContract = 0xCF14DbcfFA6E99A444539aBbc9aE273a7bb5d75A;
    
    uint256 public timesBuyHalted = 0;
    uint256 public lastHaltTimestamp = 0;
    uint256 public haltProposalStartingId = 10000000; //arbitrary starting proposal ID

    bool public withdrawalStarted = false;
    uint256 public withdrawalStartedTime = 0;
    bool public canWithdraw = false;
    uint256 public withdrawalStartedCount = 0;

    IUniswapV2Router02 public uniswapRouter;
    
    // New state variables for tracking daily usage
    mapping(uint256 => uint256) public dailyPLSUsed;
    address public immutable PAIR_ADDRESS; // DTX-PLS pair address

    constructor() {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        IERC20(0xA1077a294dDE1B09bB078844df40758a5D0f9a27).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x95B303987A60C71504D99Aa1b13B4DA07b0790ab).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        IERC20(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
        
        // Get pair address from factory
        address factory = uniswapRouter.factory();
        PAIR_ADDRESS = IUniswapV2Factory(factory).getPair(DTX, wPLS);
        require(PAIR_ADDRESS != address(0), "Pair does not exist");
    }

    // Helper function to get current UTC day
    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    // Function to get PLS balance in the pool
    function getPLSPoolBalance() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(PAIR_ADDRESS).getReserves();
        // Determine which token is PLS based on token ordering in the pair
        return IUniswapV2Pair(PAIR_ADDRESS).token0() == wPLS ? reserve0 : reserve1;
    }

    // Function to get remaining daily allowance
    function getRemainingDailyAllowance() public view returns (uint256) {
        uint256 poolBalance = getPLSPoolBalance();
        uint256 maxDaily = (poolBalance * MAX_DAILY_PERCENT) / 100;
        uint256 used = dailyPLSUsed[getCurrentDay()];
        return used >= maxDaily ? 0 : maxDaily - used;
    }

    function buyWithPLS() public {
        require(msg.sender == tx.origin);
        
        uint256 currentDay = getCurrentDay();
        uint256 _swapAmount = address(this).balance;

        // Check daily limit
        uint256 poolBalance = getPLSPoolBalance();
        uint256 maxDaily = (poolBalance * MAX_DAILY_PERCENT) / 100;
        uint256 currentDayUsed = dailyPLSUsed[currentDay];
        if(currentDayUsed + _swapAmount > maxDaily) { 
            _swapAmount = maxDaily - currentDayUsed; 
            if(_swapAmount > MAX_SWAP) {
                _swapAmount = MAX_SWAP;
            }
        }

        require(lastHaltTimestamp + 86400 < block.timestamp, "Buying is halted");

        uint deadline = block.timestamp + 15;
        uint[] memory _minOutT = getEstimatedDTXforETH();
        uint _minOut = _minOutT[_minOutT.length-1] * 99 / 100;
        
        // Update daily usage before swap
        dailyPLSUsed[currentDay] = currentDayUsed + _swapAmount;
        
        uniswapRouter.swapETHForExactTokens{ value: _swapAmount }(_minOut, getPLSpath(), address(this), deadline);
        IERC20(DTX).transfer(treasury(), IERC20(DTX).balanceOf(address(this)));
    }

    // Rest of the contract remains the same...
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
    
    function withdrawERC(address _a) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        require(IERC20(_a).transfer(treasury(), IERC20(_a).balanceOf(address(this))));
    }
    
    function enableToken(address _token) external {
        IERC20(_token).approve(UNISWAP_ROUTER_ADDRESS, type(uint256).max);
    }

    function getEstimatedDTXforETH() public view returns (uint[] memory) {
        uint256 _swapAmount = address(this).balance;
        if(_swapAmount > MAX_SWAP) { _swapAmount = MAX_SWAP; }
        return uniswapRouter.getAmountsOut(_swapAmount, getPLSpath());
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

    //
    function haltBuy() external {
        if(IVoting(votingCreditContract).burnedForId(haltProposalStartingId + timesBuyHalted) > 300000 * 1e18) {
            lastHaltTimestamp = block.timestamp;
            timesBuyHalted++;
        }
    }

    function emergencyWithdraw() external {
        require(!canWithdraw, "withdrawal already enabled");
        if(!withdrawalStarted) {
            require(IVoting(votingCreditContract).burnedForId(haltProposalStartingId + 1000 + withdrawalStartedCount) > 500000 * 1e18, "insufficient burned voting credit");   
            withdrawalStarted = true;
            withdrawalStartedTime = block.timestamp;
        } else {
            require(block.timestamp > withdrawalStartedTime + 20 hours, "must wait 20hours");// after 20 hours
                if(IVoting(votingCreditContract).burnedForId(haltProposalStartingId + 1000 + withdrawalStartedCount) >
                                    IVoting(votingCreditContract).burnedForId(haltProposalStartingId + 1000 + withdrawalStartedCount + 1)) {
                    canWithdraw = true;
                } else {
                    withdrawalStarted = false;
                    withdrawalStartedCount = withdrawalStartedCount + 2;
                }
            }
        }
    

    function withdrawToken(address _token) external {
        require(canWithdraw, "Withdrawal not allowed");
        require(IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this))));
    }

    function withdrawPLS() external {
        require(canWithdraw, "Withdrawal not allowed");
        payable(treasury()).transfer(address(this).balance);
    }

    receive() external payable {}
    fallback() external payable {}
}
