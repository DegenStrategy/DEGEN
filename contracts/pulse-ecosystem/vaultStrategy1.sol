// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";


import "../interface/IGovernor.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IActuatorChef.sol";

/**
 * Token vault (hex, inc, plsx)
 */
contract tokenVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
		uint256 debt;
		uint256 feesPaid;
		uint256 lastAction;
    }

    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }
	
	uint256 public constant maxFee = 2500; // max 25%
	uint256 public constant maxFundingFee = 1000; // max 0.1% per hour
	
    IERC20 public immutable token; //  token

    IERC20 public immutable stakeToken; // plsx, inc, hex

    IMasterChef public masterchef;  

	uint256 public vaultBalance = 0; //commissions belonging to the vault

	address public actuatorChef = 0x4469A40D4243aC1c6cF350d99B6d69b49b5005F1;
	address public rewardToken = 0x85DF7cE20A4CE0cF859804b45cB540FFE42074Da;

	address public manageRewardsAddress = ;

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option

	// Referral system: Track referrer + referral points
	mapping(address => address) public referredBy;
	mapping(address => uint256) public referralPoints;

	uint256 public poolID; 
	uint256 public actuatorPoolId;
	uint256 public accDtxPerShare;
    address public treasury; // fee address in chef
	address public treasuryWallet; // Actual treasury wallet

	uint256 public lastCredit; // Keep track of our latest credit score from masterchef
	
    uint256 public defaultDirectPayout = 50; //0.5% if withdrawn into wallet
	
	uint256 public depositFee = 0; // 0
	uint256 public fundingRate = 0;// 0
	uint256 public lastFundingChangeTimestamp; // save block.timestamp when funding rate is changed
	

    event Deposit(address indexed sender, uint256 amount, uint256 debt, uint256 depositFee, address indexed referral);
    event Withdraw(address indexed sender, uint256 stakeID, uint256 harvestAmount, uint256 penalty);

    event SelfHarvest(address indexed user, address indexed harvestInto, uint256 harvestAmount, uint256 penalty);
	
	event CollectedFee(address indexed from, uint256 amount);

 
    constructor() {
        stakeToken = IERC20();
        masterchef = IMasterChef();
        poolID = ;
		actuatorPoolId = ;
	token = IERC20();

		poolPayout[].amount = 100;
        poolPayout[].minServe = 864000;

        poolPayout[].amount = 300;
        poolPayout[].minServe = 2592000;

        poolPayout[].amount = 1000;
        poolPayout[].minServe = 8640000;

        poolPayout[].amount = 10000;
        poolPayout[].minServe = 31536000; 

	IERC20(stakeToken).approve(actuatorChef, type(uint256).max);
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier decentralizedVoting() {
        require(msg.sender == IMasterChef(masterchef).owner(), "Decentralized Voting Only!");
        _;
    }

	
    /**
     * Creates a NEW stake
     */
    function deposit(uint256 _amount, address referral) external nonReentrant {
        require(_amount > 0, "invalid amount");
        harvest();
		stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
		
		if(referredBy[msg.sender] == address(0) && referral != msg.sender) {
			referredBy[msg.sender] = referral;
		}

		uint256 _depositFee = 0;
		if(depositFee != 0) {
			_depositFee = _amount * depositFee / 10000;
			_amount = _amount - _depositFee;
		
        	stakeToken.safeTransfer(treasuryWallet, _depositFee);
		}
		
		uint256 _debt = accDtxPerShare;

		// Solves if there is 
		(uint256 _before, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		IActuatorChef(actuatorChef).deposit(actuatorPoolId, _amount);
		(uint256 _after, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		uint256 _userAmount = _after - _before;

        userInfo[msg.sender].push(
                UserInfo(_userAmount, _debt, _depositFee, block.timestamp)
            );

        emit Deposit(msg.sender, _amount, _debt, _depositFee, referredBy[msg.sender]);
    }

    /**
     * Harvests into pool
     */
    function harvest() public {
        IMasterChef(masterchef).updatePool(poolID);
		uint256 _currentCredit = IMasterChef(masterchef).credit(address(this));
		uint256 _accumulatedRewards = _currentCredit - lastCredit;
		lastCredit = _currentCredit;
		(uint256 _amount, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		accDtxPerShare+= _accumulatedRewards * 1e12  / (_amount - vaultBalance);
    }

	function initialize() external {
		(uint256 _amount, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		require(_amount == 0, "only initialization allowed");
		IActuatorChef(actuatorChef).deposit(actuatorPoolId, stakeToken.balanceOf(address(this)));
	}

	// what to do with the accumulated rewards here
	function useRewards() external {
		 IActuatorChef(actuatorChef).withdraw(actuatorPoolId, 0);
		IERC20(rewardToken).transfer(manageRewardsAddress, IERC20(rewardToken).balanceOf(address(this)));
}


    /**
     * Withdraws all tokens
     */
    function withdraw(uint256 _stakeID, address _harvestInto) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];

		
		payFee(user, msg.sender);

		//if there is withdraw fee
		uint256 _before = IERC20(stakeToken).balanceOf(address(this));
		IActuatorChef(actuatorChef).withdraw(actuatorPoolId, user.amount);
		uint256 _after = IERC20(stakeToken).balanceOf(address(this));
		uint256 userTokens = _after - _before;
		uint256 currentAmount = user.amount * (accDtxPerShare - user.debt) / 1e12;

		
		_removeStake(msg.sender, _stakeID);

        uint256 _toWithdraw;      

        if(_harvestInto == msg.sender) { 
            _toWithdraw = currentAmount * defaultDirectPayout / 10000;
            currentAmount = currentAmount - _toWithdraw;
            IMasterChef(masterchef).publishTokens(msg.sender, _toWithdraw);
        } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = currentAmount * poolPayout[_harvestInto].amount / 10000;
            currentAmount = currentAmount - _toWithdraw;
			IMasterChef(masterchef).publishTokens(address(this), _toWithdraw);
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }

		if(referredBy[msg.sender] != address(0)) {
			referralPoints[msg.sender]+= _toWithdraw;
			referralPoints[referredBy[msg.sender]]+= _toWithdraw;
		}

		if(currentAmount > 0) {
        	IMasterChef(masterchef).publishTokens(treasury, currentAmount); //penalty goes to governing contract
		}
		
		lastCredit = lastCredit - (_toWithdraw + currentAmount);
		
		emit Withdraw(msg.sender, _stakeID, _toWithdraw, currentAmount);

        stakeToken.safeTransfer(msg.sender, userTokens);
    } 


	function selfHarvest(uint256[] calldata _stakeID, address _harvestInto) external nonReentrant {
        require(_stakeID.length <= userInfo[msg.sender].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[msg.sender];
        harvest();
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;

        for(uint256 i = 0; i<_stakeID.length; ++i) {
		payFee(user[_stakeID[i]], msg.sender);
            _toWithdraw+= user[_stakeID[i]].amount * (accDtxPerShare - user[_stakeID[i]].debt)/ 1e12;
			user[_stakeID[i]].debt = accDtxPerShare;
        }

        if(_harvestInto == msg.sender) {
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            IMasterChef(masterchef).publishTokens(msg.sender, _payout); 
		} else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
			IMasterChef(masterchef).publishTokens(address(this), _payout);
            IacPool(_harvestInto).giftDeposit(_payout, msg.sender, poolPayout[_harvestInto].minServe);
		}

		if(referredBy[msg.sender] != address(0)) {
			referralPoints[msg.sender]+= _payout;
			referralPoints[referredBy[msg.sender]]+= _payout;
		}

        uint256 _penalty = _toWithdraw - _payout;
		IMasterChef(masterchef).publishTokens(treasury, _penalty); //penalty to treasury
		
		lastCredit = lastCredit - (_payout + _penalty);

		emit SelfHarvest(msg.sender, _harvestInto, _payout, _penalty);        
    }

	// emergency withdraw, without caring about rewards
	function emergencyWithdraw(uint256 _stakeID) public nonReentrant {
		require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
		UserInfo storage user = userInfo[msg.sender][_stakeID];

        payFee(user, msg.sender);
		//if there is withdraw fee
		uint256 _before = IERC20(stakeToken).balanceOf(address(this));
		IActuatorChef(actuatorChef).withdraw(actuatorPoolId, user.amount);
		uint256 _after = IERC20(stakeToken).balanceOf(address(this));
		uint256 _amount = _after - _before;
		
		_removeStake(msg.sender, _stakeID); //delete the stake
        emit Withdraw(msg.sender, _stakeID, 0, _amount);
        stakeToken.safeTransfer(msg.sender, _amount);
	}

	function emergencyWithdrawAll() external {
		uint256 _stakeID = userInfo[msg.sender].length;
		while(_stakeID > 0) {
			_stakeID--;
			emergencyWithdraw(_stakeID);
		}
	}
	
	function collectCommission(address[] calldata _beneficiary, uint256[][] calldata _stakeID) external nonReentrant {
		harvest();
		for(uint256 i = 0; i< _beneficiary.length; ++i) {
			for(uint256 j = 0; j< _stakeID[i].length; ++j) {
                UserInfo storage user = userInfo[_beneficiary[i]][_stakeID[i][j]];
                payFee(user, _beneficiary[i]);
            }
		}
		collectVaultsCommission();
	}
	
	function collectCommissionAuto(address[] calldata _beneficiary) external nonReentrant {
		harvest();
		for(uint256 i = 0; i< _beneficiary.length; ++i) {
			
			uint256 _nrOfStakes = getNrOfStakes(_beneficiary[i]);
			
			for(uint256 j = 0; j < _nrOfStakes; ++j) {
                UserInfo storage user = userInfo[_beneficiary[i]][j];
                payFee(user, _beneficiary[i]);
            }
		}
		collectVaultsCommission();
	}

	function updateFees() external {
		uint256 _depositFee = IGovernor(IMasterChef(masterchef).owner()).depositFee();
		uint256 _fundingRate = IGovernor(IMasterChef(masterchef).owner()).fundingRate();

		require(_depositFee <= maxFee, "out of limit");
		require(_fundingRate <= maxFundingFee, "out of limit");

		depositFee = _depositFee;

		if(_fundingRate != fundingRate) {
			fundingRate = _fundingRate;
			lastFundingChangeTimestamp = block.timestamp;
		} 
	}

	function updateTreasury() external {
		treasury = IMasterChef(masterchef).feeAddress();
		treasuryWallet = IGovernor(IMasterChef(masterchef).owner()).treasuryWallet();
	}
	
	
	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external decentralizedVoting {
		IERC20(_tokenAddress).safeTransfer(treasuryWallet, IERC20(_tokenAddress).balanceOf(address(this)));
	}

	/*
	 * Unlikely, but Masterchef can be changed if needed to be used without changing pools
	 * masterchef = IMasterChef(token.owner());
	 * Must stop earning first(withdraw tokens from old chef)
	*/
	function setMasterChefAddress(IMasterChef _masterchef, uint256 _newPoolID) external decentralizedVoting {
		masterchef = _masterchef;
		poolID = _newPoolID; //in case pool ID changes
	}

    //need to set pools before launch or perhaps during contract launch
    //determines the payout depending on the pool. could set a governance process for it(determining amounts for pools)
	//allocation contract contains the decentralized proccess for updating setting, but so does the admin(governor)
    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external decentralizedVoting {
		require(_amount <= 10000, "out of range"); 
		poolPayout[_poolAddress].amount = _amount;
		poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
    }

    function updateRewardAddress(address _address) external decentralizedVoting {
		manageRewardsAddress = _address;
	}

    function updateSettings(uint256 _defaultDirectHarvest) external decentralizedVoting {
		require(_defaultDirectHarvest <= 10_000, "maximum 100%");
        defaultDirectPayout = _defaultDirectHarvest;
    }

	function collectVaultsCommission() public {
		IActuatorChef(actuatorChef).withdraw(actuatorPoolId, vaultBalance);
		vaultBalance = 0;
		IERC20(stakeToken).safeTransfer(treasuryWallet, IERC20(stakeToken).balanceOf(address(this)));
	}
    
    function viewStakeEarnings(address _user, uint256 _stakeID) external view returns (uint256) {
		UserInfo storage _stake = userInfo[_user][_stakeID];
        uint256 _pending = _stake.amount * (virtualAccDtxPerShare() - _stake.debt) / 1e12 ;
        return _pending;
    }

    function viewUserTotalEarnings(address _user) external view returns (uint256) {
        UserInfo[] storage _stake = userInfo[_user];
        uint256 nrOfUserStakes = _stake.length;

		uint256 _totalPending = 0;
		
		for(uint256 i=0; i < nrOfUserStakes; ++i) {
			_totalPending+= _stake[i].amount * (virtualAccDtxPerShare() - _stake[i].debt) / 1e12 ;
		}
		
		return _totalPending;
    }
	//we want user deposit, we want total deposited, we want pending rewards, 
	function multiCall(address _user, uint256 _stakeID) external view returns(uint256, uint256, uint256, uint256) {
		UserInfo storage user = userInfo[_user][_stakeID];
		uint256 _pending = user.amount * (virtualAccDtxPerShare() - user.debt) / 1e12 ;
		(uint256 _amount, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		return(user.amount, user.feesPaid, (_amount - vaultBalance), _pending);
	}

    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingDtx(poolID));
    }

	function viewPoolPayout(address _contract) external view returns (uint256) {
		return poolPayout[_contract].amount;
	}

	function viewPoolMinServe(address _contract) external view returns (uint256) {
		return poolPayout[_contract].minServe;
	}

	/**
     * Returns number of stakes for a user
     */
    function getNrOfStakes(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

	//public lookup for UI
    function publicBalanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID); 
        uint256 _credit = IMasterChef(masterchef).credit(address(this));
        return _credit + amount;
    }

	// With "Virtual harvest" for external calls
	function virtualAccDtxPerShare() public view returns (uint256) {
		uint256 _pending = IMasterChef(masterchef).pendingDtx(poolID);
		(uint256 _amount, ) = IActuatorChef(actuatorChef).userInfo(actuatorPoolId, address(this));
		return (accDtxPerShare + _pending * 1e12  / (_amount - vaultBalance));
	}

    function payFee(UserInfo storage user, address _userAddress) private {
		uint256 _lastAction = user.lastAction;

		// Prevents charging new funding fee for the past (in case funding fee changes)
		// Before funding fee is changed, commissions must be manually collected
		if(lastFundingChangeTimestamp > _lastAction) {
			user.lastAction = lastFundingChangeTimestamp;
			_lastAction = lastFundingChangeTimestamp;
		}

        uint256 secondsSinceLastaction = block.timestamp - _lastAction;
				
		if(secondsSinceLastaction >= 3600  && fundingRate > 0) {
			user.lastAction = block.timestamp - (secondsSinceLastaction % 3600);
			
			uint256 commission = (block.timestamp - _lastAction) / 3600 * user.amount * fundingRate / 1000000;

			if(commission > user.amount * 2 / 10) {
				commission = user.amount * 2 / 10;
			}
			
		vaultBalance+= commission;

            user.feesPaid = user.feesPaid + commission;
			
			user.amount = user.amount - commission;
			
			emit CollectedFee(_userAddress, commission);
		}
	}


    /**
     * removes the stake
     */
    function _removeStake(address _staker, uint256 _stakeID) private {
        UserInfo[] storage stakes = userInfo[_staker];
        uint256 lastStakeID = stakes.length - 1;
        
        if(_stakeID != lastStakeID) {
            stakes[_stakeID] = stakes[lastStakeID];
        }
        
        stakes.pop();
    }
}

