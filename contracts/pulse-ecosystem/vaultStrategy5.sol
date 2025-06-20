// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";


import "../interface/IGovernor.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IDTX.sol";

interface IHelperToken {
	function mint(address to, uint256 amount) external;
}

interface IFarm {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);

    function claimReward() external;
}

/**
 * on inc printer for inc/print
 */
contract tokenVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
		uint256 debt;
		uint256 feesPaid;
		uint256 lastAction;
    }

	address public immutable INC = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d;
    address public immutable INCD = 0x144Cd22AaA2a80FEd0Bb8B1DeADDc51A53Df1d50;
    address public immutable PRINT = 0x6C203A555824ec90a215f37916cf8Db58EBe2fA3;
	IERC20 public constant stakeToken = IERC20(0x2cb92b1e8B2fC53b5A9165E765488e17B38C26D3); //INC - INCD LP

	uint256 public constant maxFee = 2500; // max 25%
	uint256 public constant maxFundingFee = 1000; // max 0.1% per hour
	
    address public immutable token; //  token
	address public helperToken;


    IMasterChef public masterchef;  

	uint256 public vaultBalance = 0; //commissions belonging to the vault

	IFarm stakingContract = IFarm(0x5A0D3cC13A523Dd7A9279C5Eb4f363593dA4198e);


	address public manageRewardsAddress;

    mapping(address => UserInfo[]) public userInfo;

	// Referral system: Track referrer + referral points
	mapping(address => address) public referredBy;
	mapping(address => uint256) public referralPoints;

	uint256 public poolID; 
	uint256 public actuatorPoolId;
	uint256 public accDtxPerShare;
	address public treasuryWallet; // Actual treasury wallet

	uint256 public lastCredit; // Keep track of our latest credit score from masterchef
	
	uint256 public depositFee = 0; // 0
	uint256 public fundingRate = 0;// 0
	uint256 public lastFundingChangeTimestamp; // save block.timestamp when funding rate is changed
	

    event Deposit(address indexed sender, uint256 amount, uint256 debt, uint256 depositFee, address indexed referral);
    event Withdraw(address indexed sender, uint256 stakeID, uint256 harvestAmount);

    event SelfHarvest(address indexed user, uint256 harvestAmount);
	
	event CollectedFee(address indexed from, uint256 amount);

 
    constructor() {
        poolID = 8;
	token = ;

	IERC20(stakeToken).approve(address(stakingContract), type(uint256).max);
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
		uint256 _before = stakingContract.balanceOf(address(this));
		stakingContract.stake(_amount);
		uint256 _after = stakingContract.balanceOf(address(this));
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
		uint256 _amount = stakingContract.balanceOf(address(this));
		accDtxPerShare+= _accumulatedRewards * 1e12  / (_amount - vaultBalance);
    }

	function initialize() external {
		uint256 _amount = stakingContract.balanceOf(address(this));
		require(_amount == 0, "only initialization allowed");
		stakingContract.stake(stakeToken.balanceOf(address(this)));
	}

	// what to do with the accumulated rewards here
	function useRewards() external {
		stakingContract.claimReward();

		IERC20(PRINT).transfer(manageRewardsAddress, IERC20(PRINT).balanceOf(address(this))); 
        IERC20(INC).transfer(manageRewardsAddress, IERC20(INC).balanceOf(address(this))); 
        IERC20(INCD).transfer(manageRewardsAddress, IERC20(INCD).balanceOf(address(this))); 
}


    /**
     * Withdraws all tokens
     */
    function withdraw(uint256 _stakeID) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];

		
		payFee(user, msg.sender);

		//if there is withdraw fee
		uint256 _before = IERC20(stakeToken).balanceOf(address(this));
		stakingContract.withdraw(user.amount);
		uint256 _after = IERC20(stakeToken).balanceOf(address(this));
		uint256 userTokens = _after - _before;
		uint256 currentAmount = user.amount * (accDtxPerShare - user.debt) / 1e12;

		
		_removeStake(msg.sender, _stakeID);

		IMasterChef(masterchef).transferCredit(helperToken, currentAmount);
		IHelperToken(helperToken).mint(msg.sender, currentAmount);

		if(referredBy[msg.sender] != address(0)) {
			referralPoints[msg.sender]+= currentAmount;
			referralPoints[referredBy[msg.sender]]+= currentAmount;
		}

		lastCredit = lastCredit - currentAmount;
		
		emit Withdraw(msg.sender, _stakeID, currentAmount);

        stakeToken.safeTransfer(msg.sender, userTokens);
    } 

	function selfHarvest(address _userAddress, uint256[] calldata _stakeID) external nonReentrant {
        require(_stakeID.length <= userInfo[_userAddress].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[_userAddress];
        harvest();
        uint256 _toWithdraw = 0;

        for(uint256 i = 0; i<_stakeID.length; ++i) {
		payFee(user[_stakeID[i]], _userAddress);
            _toWithdraw+= user[_stakeID[i]].amount * (accDtxPerShare - user[_stakeID[i]].debt)/ 1e12;
			user[_stakeID[i]].debt = accDtxPerShare;
        }

        IMasterChef(masterchef).transferCredit(helperToken, _toWithdraw);
		IHelperToken(helperToken).mint(_userAddress, _toWithdraw);

		if(referredBy[_userAddress] != address(0)) {
			referralPoints[_userAddress]+= _toWithdraw;
			referralPoints[referredBy[_userAddress]]+= _toWithdraw;
		}
		
		lastCredit = lastCredit - _toWithdraw;

		emit SelfHarvest(_userAddress, _toWithdraw);        
    }

	// emergency withdraw, without caring about rewards
	function emergencyWithdraw(uint256 _stakeID) public nonReentrant {
		require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
		UserInfo storage user = userInfo[msg.sender][_stakeID];

        payFee(user, msg.sender);
		//if there is withdraw fee
		uint256 _before = IERC20(stakeToken).balanceOf(address(this));
		stakingContract.withdraw(user.amount);
		uint256 _after = IERC20(stakeToken).balanceOf(address(this));
		uint256 _amount = _after - _before;
		
		_removeStake(msg.sender, _stakeID); //delete the stake
        emit Withdraw(msg.sender, _stakeID, _amount);
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

	function updateAddresses() external {
		masterchef = IMasterChef(IDTX(token).masterchefAddress());
		manageRewardsAddress = IGovernor(IMasterChef(masterchef).owner()).manageRewardsAddress();
		treasuryWallet = IGovernor(IMasterChef(masterchef).owner()).treasuryWallet();
		helperToken = IGovernor(IMasterChef(masterchef).owner()).helperToken();
	}
	
	
	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external decentralizedVoting {
		IERC20(_tokenAddress).safeTransfer(treasuryWallet, IERC20(_tokenAddress).balanceOf(address(this)));
	}

	function collectVaultsCommission() public {
		stakingContract.withdraw(vaultBalance);
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
		uint256 _amount = stakingContract.balanceOf(address(this));
		return(user.amount, user.feesPaid, (_amount - vaultBalance), _pending);
	}

    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingDtx(poolID));
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
		uint256 _amount = stakingContract.balanceOf(address(this));
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

