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

interface I2phux {
    event ArbitratorUpdated(address newArbitrator);
    event Deposited(
        address indexed user,
        uint256 indexed poolid,
        uint256 amount
    );
    event FactoriesUpdated(
        address rewardFactory,
        address stashFactory,
        address tokenFactory
    );
    event FeeInfoChanged(address feeDistro, bool active);
    event FeeInfoUpdated(address feeDistro, address lockFees, address feeToken);
    event FeeManagerUpdated(address newFeeManager);
    event FeesUpdated(
        uint256 lockIncentive,
        uint256 stakerIncentive,
        uint256 earmarkIncentive,
        uint256 platformFee
    );
    event OwnerUpdated(address newOwner);
    event PoolAdded(
        address lpToken,
        address gauge,
        address token,
        address rewardPool,
        address stash,
        uint256 pid
    );
    event PoolManagerUpdated(address newPoolManager);
    event PoolShutdown(uint256 poolId);
    event RewardContractsUpdated(address lockRewards, address stakerRewards);
    event TreasuryUpdated(address newTreasury);
    event VoteDelegateUpdated(address newVoteDelegate);
    event Withdrawn(
        address indexed user,
        uint256 indexed poolid,
        uint256 amount
    );

    function FEE_DENOMINATOR() external view returns (uint256);

    function MaxFees() external view returns (uint256);

    function REWARD_MULTIPLIER_DENOMINATOR() external view returns (uint256);

    function addPool(
        address _lptoken,
        address _gauge,
        uint256 _stashVersion
    ) external returns (bool);

    function bridgeDelegate() external view returns (address);

    function claimRewards(uint256 _pid, address _gauge) external returns (bool);

    function crv() external view returns (address);

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);

    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function distributeL2Fees(uint256 _amount) external;

    function earmarkFees(address _feeToken) external returns (bool);

    function earmarkIncentive() external view returns (uint256);

    function earmarkRewards(uint256 _pid) external returns (bool);

    function feeManager() external view returns (address);

    function feeTokens(address)
        external
        view
        returns (
            address distro,
            address rewards,
            bool active
        );

    function gaugeMap(address) external view returns (bool);

    function getRewardMultipliers(address) external view returns (uint256);

    function isShutdown() external view returns (bool);

    function l2FeesHistory(uint256) external view returns (uint256);

    function lockIncentive() external view returns (uint256);

    function lockRewards() external view returns (address);

    function minter() external view returns (address);

    function owner() external view returns (address);

    function platformFee() external view returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );

    function poolLength() external view returns (uint256);

    function poolManager() external view returns (address);

    function rewardArbitrator() external view returns (address);

    function rewardClaimed(
        uint256 _pid,
        address _address,
        uint256 _amount
    ) external returns (bool);

    function rewardFactory() external view returns (address);

    function setArbitrator(address _arb) external;

    function setBridgeDelegate(address _bridgeDelegate) external;

    function setDelegate(
        address _delegateContract,
        address _delegate,
        bytes32 _space
    ) external;

    function setFactories(
        address _rfactory,
        address _sfactory,
        address _tfactory
    ) external;

    function setFeeInfo(address _feeToken, address _feeDistro) external;

    function setFeeManager(address _feeM) external;

    function setFees(
        uint256 _lockFees,
        uint256 _stakerFees,
        uint256 _callerFees,
        uint256 _platform
    ) external;

    function setGaugeRedirect(uint256 _pid) external returns (bool);

    function setOwner(address _owner) external;

    function setPoolManager(address _poolM) external;

    function setRewardContracts(address _rewards, address _stakerRewards)
        external;

    function setRewardMultiplier(address rewardContract, uint256 multiplier)
        external;

    function setTreasury(address _treasury) external;

    function setVote(bytes32 _hash) external returns (bool);

    function setVoteDelegate(address _voteDelegate) external;

    function shutdownPool(uint256 _pid) external returns (bool);

    function shutdownSystem() external;

    function staker() external view returns (address);

    function stakerIncentive() external view returns (uint256);

    function stakerRewards() external view returns (address);

    function stashFactory() external view returns (address);

    function tokenFactory() external view returns (address);

    function treasury() external view returns (address);

    function updateFeeInfo(address _feeToken, bool _active) external;

    function vote(
        uint256 _voteId,
        address _votingAddress,
        bool _support
    ) external returns (bool);

    function voteDelegate() external view returns (address);

    function voteGaugeWeight(address[] memory _gauge, uint256[] memory _weight)
        external
        returns (bool);

    function voteOwnership() external view returns (address);

    function voteParameter() external view returns (address);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);

    function withdrawTo(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external returns (bool);
}

interface IBaseRewardPool {
    function balanceOf(address account) external view returns (uint256);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
}


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
	
	uint256 public constant maxFee = 2500; // max 25%
	uint256 public constant maxFundingFee = 1000; // max 0.1% per hour
	
    address public immutable token; //  token

    IERC20 public immutable stakeToken; // plsx, inc, hex

    IMasterChef public masterchef;  

	uint256 public vaultBalance = 0; //commissions belonging to the vault

	address public actuatorChef = 0x7bDCFCc86F69e52eF2866251b8a1ef162AB10368;
	address public rewardToken = 0x9663c2d75ffd5F4017310405fCe61720aF45B829;
    address public rewardToken2 = 0x115f3Fa979a936167f9D208a7B7c4d85081e84BD;
    address public rewardContract = 0x26d0f015BFcf722c180587200FA6bf62Fb420152;

	address public manageRewardsAddress;
    address public helperToken;

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
        stakeToken = IERC20(0x30dD5508C3b1DEB46a69FE29955428Bb4E0733d9);
        poolID = 16;
		actuatorPoolId = 114;
	token = ;


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
		uint256 _before = IBaseRewardPool(rewardContract).balanceOf(address(this));
		I2phux(actuatorChef).deposit(actuatorPoolId, _amount, true);
		uint256 _after = IBaseRewardPool(rewardContract).balanceOf(address(this));
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
		uint256 _amount = IBaseRewardPool(rewardContract).balanceOf(address(this));
		accDtxPerShare+= _accumulatedRewards * 1e12  / (_amount - vaultBalance);
    }

	function initialize() external {
		uint256 _amount = IBaseRewardPool(rewardContract).balanceOf(address(this));
		require(_amount == 0, "only initialization allowed");
		I2phux(actuatorChef).deposit(actuatorPoolId, stakeToken.balanceOf(address(this)), true);
	}

	// what to do with the accumulated rewards here
	function useRewards() external {
        IBaseRewardPool(rewardContract).withdrawAndUnwrap(0, true);
		IERC20(rewardToken).transfer(manageRewardsAddress, IERC20(rewardToken).balanceOf(address(this)));
        IERC20(rewardToken2).transfer(manageRewardsAddress, IERC20(rewardToken2).balanceOf(address(this)));
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
        IBaseRewardPool(rewardContract).withdrawAndUnwrap(user.amount, false);
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
        IBaseRewardPool(rewardContract).withdrawAndUnwrap(user.amount, false);
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
		manageRewardsAddress = IMasterChef(masterchef).feeAddress();
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
        IBaseRewardPool(rewardContract).withdrawAndUnwrap(vaultBalance, false);
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
		uint256 _amount = IBaseRewardPool(rewardContract).balanceOf(address(this));
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
		uint256 _amount = IBaseRewardPool(rewardContract).balanceOf(address(this));
		return (accDtxPerShare + _pending * 1e12  / (_amount - vaultBalance));
	}

    function getRewardContractBalance() external view returns(uint256) {
        return IBaseRewardPool(rewardContract).balanceOf(address(this));
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

