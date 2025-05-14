// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IMasterChef.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IacPool.sol";
import "./interface/ITreasury.sol";

interface ITokenBalancer {
    function emergencyWithdraw(address _token) external;
}

contract DTXgovernor {
    address public constant token = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38; //XPD token
    bool public changedName = false;

    //masterchef address
    address public constant masterchef = 0x486fEa20eA242456b450B005ED7D019E3E984f28;

	address public constant basicContract = 0x5DebADaf41ED55270e0F9944FD389745e73d29B9;
	address public constant farmContract = 0x0dc0Fabe4c9d57cCaD055b4cD627D0d24fA3C98E;
    address public constant consensusContract = 0x7917e04Eb4463CF80Cc00040BA0f1fF125926eF3;
	
	address public constant creditContract = 0xCF14DbcfFA6E99A444539aBbc9aE273a7bb5d75A;
    
    address public constant treasuryWallet = 0x3a4DA32dc29b146F26D8527e37FeaAe45fBebe69;

	address public constant senateContract = 0x147B43930283d1DDe43d805B7f17E4604b7ca493;
	address public constant rewardContract = 0x066F0a45801bcbc5232b11ed4b97c39E1369fe59; //for referral rewards
    
    //addresses for time-locked deposits(autocompounding pools)
    address public constant acPool1 = ;
    address public constant acPool2 = ;
    address public constant acPool3 = ;

        
    //pool ID in the masterchef for respective Pool address and dummy token
    uint256 public constant acPool1ID = 0;
    uint256 public constant acPool2ID = 1;
    uint256 public constant acPool3ID = 2;

    
    mapping(address => uint256) private _rollBonus;

	uint256 public referralBonus = 500; // 5% for both referr and invitee
	uint256 public depositFee = 0;
	uint256 public fundingRate = 200;

	uint256 public mintingPhaseLaunchDate = 1738574301; //arbitrarily set
	uint256 public lastTotalCredit; // Keeps track of last total credit from chef (sends 2.5% to reward contract)
    
    uint256 public costToVote = 1000 * 1e18;  // 1000 coins. All proposals are valid unless rejected. This is a minimum to prevent spam
    uint256 public delayBeforeEnforce = 1 days; //minimum number of TIME between when proposal is initiated and executed
    
    
    //delays for Fibonnaccening(Reward Boost) Events
    uint256 public constant minDelay = 24 hours; // has to be called minimum 1 day in advance
    uint256 public constant maxDelay = 31 days; 
    


    uint256  public totalFibonacciEventsAfterGrand; //used for rebalancing inflation after Grand Fib
    
    uint256 public newGovernorRequestBlock;
    address public eligibleNewGovernor; //used for changing smart contract
    bool public changeGovernorActivated;
	
	uint256 public lastHarvestedTime;

    event SetInflation(uint256 rewardPerBlock);
    event EnforceGovernor(address indexed _newGovernor, address indexed enforcer);
    event GiveRolloverBonus(address indexed recipient, uint256 amount, address indexed poolInto);

    constructor() {
		// Roll-over bonuses
		_rollBonus[acPool1] = 100;
		_rollBonus[acPool2] = 300;
		_rollBonus[acPool3] = 500;
    }    
   
   
     /**
     * Rebalances Pools and allocates rewards in masterchef
     * Pools with higher time-lock must always pay higher rewards in relative terms
     * Eg. for 1DTX staked in the pool 6, you should always be receiving
     * 50% more rewards compared to staking in pool 4
     */
    function rebalancePools() public {
    	uint256 balancePool1 = IacPool(acPool1).balanceOf();
    	uint256 balancePool2 = IacPool(acPool2).balanceOf();
    	uint256 balancePool3 = IacPool(acPool3).balanceOf();
    	
   	    uint256 total = balancePool1 + balancePool2 + balancePool3;

		IMasterChef(masterchef).set(acPool1ID, (100000 * 5333 * balancePool1) / (total * 10000), true);
    	IMasterChef(masterchef).set(acPool2ID, (100000 * 25000 * balancePool2) / (total * 10000), false);
    	IMasterChef(masterchef).set(acPool3ID, (100000 * 125000 * balancePool3) / (total * 10000), false);
    }
	

    /**
     * Harvests from all pools and rebalances rewards
     */
    function harvest() external {
        rebalancePools();
		lastHarvestedTime = block.timestamp;
    }
    
    /**
     * Mechanism, where the governor gives the bonus 
     * to user for extending(re-commiting) their stake
     * tldr; sends the gift deposit, which resets the timer
     * the pool is responsible for calculating the bonus
     */
    function stakeRolloverBonus(address _toAddress, address _depositToPool, uint256 _bonusToPay, uint256 _stakeID) external {
        require(
            msg.sender == acPool1 || msg.sender == acPool2 || msg.sender == acPool3);
        
        IacPool(_depositToPool).addAndExtendStake(_toAddress, _bonusToPay, _stakeID, 0);
        
        emit GiveRolloverBonus(_toAddress, _bonusToPay, _depositToPool);
    }
    
    
    function enforceGovernor() external {
        require(msg.sender == consensusContract);
		require(newGovernorRequestBlock + newGovernorBlockDelay() < block.number, "time delay not yet passed");

		IMasterChef(masterchef).setFeeAddress(eligibleNewGovernor);
        IMasterChef(masterchef).dev(eligibleNewGovernor);
        IMasterChef(masterchef).transferOwnership(eligibleNewGovernor); //transfer masterchef ownership
		
		IERC20(token).transfer(eligibleNewGovernor, IERC20(token).balanceOf(address(this))); // send collected DTX tokens to new governor
        
		emit EnforceGovernor(eligibleNewGovernor, msg.sender);
    }
	
    function setNewGovernor(address beneficiary) external {
        require(msg.sender == consensusContract);
        newGovernorRequestBlock = block.number;
        eligibleNewGovernor = beneficiary;
        changeGovernorActivated = true;
    }
	
	function governorRejected() external {
		require(changeGovernorActivated, "not active");
		
		(bool _govInvalidated, ) = IConsensus(consensusContract).isGovInvalidated(eligibleNewGovernor);
		if(_govInvalidated) {
			changeGovernorActivated = false;
		}
	}

	function treasuryRequest(address _tokenAddr, address _recipient, uint256 _amountToSend) external {
		require(msg.sender == consensusContract);
		ITreasury(payable(treasuryWallet)).requestWithdraw(
			_tokenAddr, _recipient, _amountToSend
		);
	}
	
	function updateDelayBeforeEnforce(uint256 newDelay) external {
	    require(msg.sender == basicContract);
	    delayBeforeEnforce = newDelay;
	}
	
	function setCallFee(address _acPool, uint256 _newCallFee) external {
	    require(msg.sender == basicContract);
	    IacPool(_acPool).setCallFee(_newCallFee);
	}
	
	function updateCostToVote(uint256 newCostToVote) external {
	    require(msg.sender == basicContract);
	    costToVote = newCostToVote;
	}
	
	function updateRolloverBonus(address _forPool, uint256 _bonus) external {
	    require(msg.sender == basicContract);
		require(_bonus <= 1500, "15% hard limit");
	    _rollBonus[_forPool] = _bonus;
	}

	function addNewPool(address _pool) external {
	    require(msg.sender == basicContract);
		require(IMasterChef(masterchef).poolLength() < 50, "Maximum pools allowed reached");
	    IMasterChef(masterchef).add(0, _pool, false);
	}

	function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external {
	    require(msg.sender == farmContract);
	    IMasterChef(masterchef).set(_pid, _allocPoint, _withUpdate);
	}

	// If fees are changed, updateFees() function must be called to each vault contract to sync the update!
	function updateVault(uint256 _type, uint256 _amount) external {
        require(msg.sender == farmContract);

        if(_type == 0) {
            depositFee = _amount;
        } else if(_type == 1) {
            fundingRate = _amount;
        } else if (_type == 2) {
			require(_amount <= 2500, "max 25% Bonus!");
			referralBonus = _amount;
		}
    }
	
	function setGovernorTax(uint256 _amount) external {
		require(msg.sender == farmContract);
		IMasterChef(masterchef).setGovernorFee(_amount);
	}

	
	function burnTokens(uint256 amount) external {
		require(msg.sender == farmContract);
		
		IDTX(token).burn(amount);
	}
	
	function transferToTreasury(uint256 amount) external {
		require(msg.sender == farmContract);
		
		IERC20(token).transfer(treasuryWallet, amount);
	}


	function getRollBonus(address _bonusForPool) external view returns (uint256) {
        return _rollBonus[_bonusForPool];
    }
	
	/* UPDATE: CHANGING SO THAT IT CHANGES BY 100 blocks per each day
	 * newGovernorBlockDelay is the delay during which the governor proposal can be voted against
	 * As the time passes, changes should take longer to enforce(greater security)
	 * Prioritize speed and efficiency at launch. Prioritize security once established
	 * Delay increases by 535 blocks(roughly 1.6hours) per each day after launch
	 * Delay starts at 42772 blocks(roughly 5 days)
	 * After a month, delay will be roughly 7 days (increases 2days/month)
	 * After a year, 29 days. After 2 years, 53 days,...
	 * Can be ofcourse changed by replacing governor contract
	 */
	function newGovernorBlockDelay() public view returns (uint256) {
		return (42772 + (((block.timestamp - mintingPhaseLaunchDate) / 86400) * 100));
	}
    
}  
