// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interface/IDTX.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";

interface IncChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}

contract Farmer {  // Changed to uppercase for contract name convention
    address public immutable incMasterchef = 0xB2Ca4A66d3e57a5a9A12043B6bAD28249fE302d4;
    address public immutable votingCreditContract = 0xCF14DbcfFA6E99A444539aBbc9aE273a7bb5d75A;
    address public immutable DTX = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public immutable INC = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d;
    address public immutable buyandburn = 0xa36d037B01C148025C54e4f86C0032F05a93D4Ce;
    bool public stopStaking = false;

    // Empty constructor is fine, but let's make it explicit
    constructor() payable {  // Added payable to make it more flexible
    }

    function harvest(uint256 _pid) public {
        IncChef(incMasterchef).withdraw(_pid, 0);
        IERC20(INC).transfer(buyandburn, IERC20(INC).balanceOf(address(this)));
    }

    function startStake(uint256 _pid, address _token) external {
        approveToken(_token);
        IncChef(incMasterchef).deposit(_pid, IERC20(_token).balanceOf(address(this)));
    }

    function approveToken(address _token) internal {
        IERC20(_token).approve(incMasterchef, type(uint256).max);
    }

    function endStake(uint256 _pid) external {
        require(stopStaking, "staking is still enabled");
        harvest(_pid);
        IncChef(incMasterchef).emergencyWithdraw(_pid);
    }

    function sendToTreasury(address _token) external {
        require(stopStaking, "staking is still enabled");
        IERC20(_token).transfer(treasury(), IERC20(_token).balanceOf(address(this)));
    }

    function governor() public view returns (address) {
        return IDTX(DTX).governor();
    }

    function treasury() public view returns (address) {
        return IGovernor(governor()).treasuryWallet();
    }

    function initiateHaltOfStaking() external {
        require(!stopStaking, "halt of staking already initiated");
        if(IVoting(votingCreditContract).burnedForId(100000000000) > 10000000 * 1e18) { //artificially chosen ID 10000000
            stopStaking = true;
        }
    }

    function haltStakingByGovernor() external {
        require(msg.sender == governor(), "governor contract only");
        stopStaking = true;
    }

    // Add receive function to accept ETH transfers if needed
    receive() external payable {}
}
