// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";


import "../interface/IGovernor.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IDTX.sol";

interface IHelperToken {
	function mint(address to, uint256 amount) external;
}

interface IEmit {
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event RewardPaid(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function BBC() external view returns (address);

    function INC() external view returns (address);

    function MAX_REWARDS_PER_SEC() external view returns (uint256);

    function NINE_INCH_MASTERCHEF() external view returns (address);

    function PULSE_X_MASTERCHEF() external view returns (address);

    function add(
        uint256 _allocPoint,
        address _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        uint8 _externalProtocol,
        address _externalFarm,
        uint256 _externalPid
    ) external;

    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;

    function depositOnBehalfOf(
        uint256 _pid,
        uint256 _amount,
        address _referrer,
        address _staker
    ) external;

    function devAddress() external view returns (address);

    function devPercent() external view returns (uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function emitToken() external view returns (address);

    function emittersNft() external view returns (address);

    function feeAddress() external view returns (address);

    function feePercent() external view returns (uint256);

    function getAllPoolViews()
        external
        view
        returns (EMISSIONS.PoolView[] memory);

    function getExternalReward(uint256 _pid) external;

    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256);

    function getPoolView(uint256 pid)
        external
        view
        returns (EMISSIONS.PoolView memory);

    function getUserView(uint256 pid, address account)
        external
        view
        returns (EMISSIONS.UserView memory);

    function getUserViews(address account)
        external
        view
        returns (EMISSIONS.UserView[] memory);

    function massUpdatePools() external;

    function multicall(bytes[] memory data)
        external
        returns (bytes[] memory results);

    function owner() external view returns (address);

    function pendingShare(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            address token,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint16 depositFeeBP,
            uint16 withdrawFeeBP,
            uint256 accTokensPerShare,
            bool isStarted,
            uint8 externalProtocol,
            address externalFarm,
            uint256 lpBalance,
            uint256 externalPid
        );

    function poolLength() external view returns (uint256);

    function referral(address) external view returns (address);

    function referralEarned(address) external view returns (uint256);

    function referralRate() external view returns (uint256);

    function removeExternalFarm(uint256 _pid) external;

    function renounceOwnership() external;

    function rewardsPerSec() external view returns (uint256);

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP
    ) external;

    function setDevAddress(address _devAddress) external;

    function setDevPercent(uint256 _devPercent) external;

    function setFeeAddress(address _feeAddress) external;

    function setFeePercent(uint256 _feePercent) external;

    function setReferralRate(uint256 _referralRate) external;

    function startTime() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updateEmissionRate(uint256 _rewardsPerSec) external;

    function updatePool(uint256 _pid) external;

    function userInfo(uint256, address)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);

    function withdraw(uint256 _pid, uint256 _amount) external;
}

interface EMISSIONS {
    struct PoolView {
        uint256 pid;
        address token;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint16 depositFeeBP;
        uint16 withdrawFeeBP;
        uint256 accTokensPerShare;
        bool isStarted;
        uint8 externalProtocol;
        address externalFarm;
        uint256 lpBalance;
        uint256 rewardsPerSecond;
    }

    struct UserView {
        uint256 pid;
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
        uint256 allowance;
    }
}



/**
 * Token vault (hex, inc, plsx)
 */
contract tokenVault is ReentrancyGuard, IERC721Receiver {
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

	address public emitChef = 0x7Cc0a0ca2f9346AceAdd5110cfa15C4FA12f9251; // "emissions contract"
	address public rewardToken = 0x32fB5663619A657839A80133994E45c5e5cDf427; // == EMIT

    IERC721 public nftContract = IERC721(0x133F4205141d869A72724910331c0f0b7235dF7b);
    uint256 public nftId = 268;

    bool public useNFT = true;

    uint256 public constant emissionsPoolId = 10; //pool id in emissions contract

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
        stakeToken = IERC20(0x46814b3f18D90625B6E166bC2917Bb64a635d797); // vpls-pls
        poolID = 16;
	token = ;


	IERC20(stakeToken).approve(emitChef, type(uint256).max);
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

        if(useNFT) {
            address _nftOwner = nftContract.ownerOf(nftId);
            if(_nftOwner != address(this)) {
                nftContract.safeTransferFrom(_nftOwner, address(this), nftId);
            }
        }
        EMISSIONS.UserView memory userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _before = userView.stakedAmount;
		IEmit(emitChef).deposit(emissionsPoolId, _amount, 0x6494d2569b81E5a6164212E641331A530a150c3b);
        userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _after = userView.stakedAmount;
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
        EMISSIONS.UserView memory userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _amount = userView.stakedAmount;
		accDtxPerShare+= _accumulatedRewards * 1e12  / (_amount - vaultBalance);
    }

	function initialize() external {
        EMISSIONS.UserView memory userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _amount = userView.stakedAmount;
		require(_amount == 0, "only initialization allowed");
		IEmit(emitChef).deposit(emissionsPoolId, 1, 0x6494d2569b81E5a6164212E641331A530a150c3b);
	}

	// what to do with the accumulated rewards here
	function useRewards() external {
		IEmit(emitChef).deposit(emissionsPoolId, 0, 0x6494d2569b81E5a6164212E641331A530a150c3b);
		IERC20(rewardToken).transfer(manageRewardsAddress, IERC20(rewardToken).balanceOf(address(this)));
}


    /**
     * Withdraws all tokens
     */
    function withdraw(uint256 _stakeID) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];

		
		payFee(user, msg.sender);

		uint256 _before = IERC20(stakeToken).balanceOf(address(this));
		IEmit(emitChef).withdraw(emissionsPoolId, user.amount);
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
        IEmit(emitChef).withdraw(emissionsPoolId, user.amount);
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
	
	function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external decentralizedVoting {
		IERC20(_tokenAddress).safeTransfer(treasuryWallet, IERC20(_tokenAddress).balanceOf(address(this)));
	}

    function withdrawNFT(address _address) external decentralizedVoting {
		nftContract.safeTransferFrom(address(this), _address, nftId);
	}

    function toUseNFT(bool _a) external decentralizedVoting {
		useNFT = _a;
	}

    function giveNFTApproval(address[] calldata _allowed, bool _permission) external decentralizedVoting {
        for(uint256 i = 0; i < _allowed.length; ++i) { 
			nftContract.setApprovalForAll(_allowed[i], _permission);
        }
    }

	function collectVaultsCommission() public {
        IEmit(emitChef).withdraw(emissionsPoolId, vaultBalance);
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
        EMISSIONS.UserView memory userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _amount = userView.stakedAmount;
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
		EMISSIONS.UserView memory userView = IEmit(emitChef).getUserView(emissionsPoolId, address(this));
		uint256 _amount = userView.stakedAmount;
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

