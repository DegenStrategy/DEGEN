// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";


import "../interface/IGovernor.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IVoting.sol";

/**
 * PLS vault
 * !!! Warning: !!! Licensed under Business Source License 1.1 (BSL 1.1)
 */
contract plsVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
		address pool;
		uint256 harvestThreshold;
        uint256 feeToPay;
		uint256 debt;
    }

    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }
	
    IERC20 public immutable token; // DTX token
    
    IERC20 public immutable dummyToken; 

    IMasterChef public masterchef;  

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option
 
	uint256 public poolID; 
	uint256 public accDtxPerShare;
    address public admin; //admin = governing contract!
    address public treasury; //penalties

    uint256 public defaultDirectPayout = 500; //5% if withdrawn into wallet
	

    event Deposit(address indexed sender, uint256 amount, address poolInto, uint256 threshold, uint256 fee, uint256 debt);
    event Withdraw(address indexed sender, uint256 stakeID, uint256 harvestAmount, uint256 penalty);
    event UserSettingUpdate(address indexed user, address poolAddress, uint256 threshold, uint256 feeToPay);

    event Harvest(address indexed harvester, address indexed benficiary, uint256 stakeID, address harvestInto, uint256 harvestAmount, uint256 penalty, uint256 callFee); //harvestAmount contains the callFee
    event SelfHarvest(address indexed user, uint256 stakeID, address harvestInto, uint256 harvestAmount, uint256 penalty);

    /**
     * @notice Constructor
     * @param _token: DTX token contract
     * @param _dummyToken: Dummy token contract
     * @param _masterchef: MasterChef contract
     * @param _admin: address of the admin
     * @param _treasury: address of the treasury (collects fees)
     */
    constructor(
        IERC20 _token,
        IERC20 _dummyToken,
        IMasterChef _masterchef,
        address _admin,
        address _treasury,
        uint256 _poolID
    ) {
        token = _token;
        dummyToken = _dummyToken;
        masterchef = _masterchef;
        admin = _admin;
        treasury = _treasury;
        poolID = _poolID;

        IERC20(_dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		poolPayout[0x32b33C2Eb712D172e389811d5621031688Fa4c13].amount = 750;
        poolPayout[0x32b33C2Eb712D172e389811d5621031688Fa4c13].minServe = 864000;

        poolPayout[0x8C0471539F226453598090dAd4333F3D7E34Afb4].amount = 1500;
        poolPayout[0x8C0471539F226453598090dAd4333F3D7E34Afb4].minServe = 2592000;

        poolPayout[0xC251392b5A5D3f0721027015D1d1234d630c8688].amount = 2500;
        poolPayout[0xC251392b5A5D3f0721027015D1d1234d630c8688].minServe = 5184000;

        poolPayout[0x7B0939A38EDc3bfDB674F4160e08A3Abed733305].amount = 5000;
        poolPayout[0x7B0939A38EDc3bfDB674F4160e08A3Abed733305].minServe = 8640000;

        poolPayout[0x2694BaB21281Bf743536754C562b8d3AA99DF80c].amount = 7000;
        poolPayout[0x2694BaB21281Bf743536754C562b8d3AA99DF80c].minServe = 20736000;

        poolPayout[0x908C35aa2CFF22e8234990344C129AD2fD365A0F].amount = 10000;
        poolPayout[0x908C35aa2CFF22e8234990344C129AD2fD365A0F].minServe = 31536000; 
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier adminOnly() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }
	
    receive() external payable {}
    fallback() external payable {}

	
    /**
     * Creates a NEW stake
     * _poolInto is the pool to harvest into(time deposit option)
	 * threshold is the amount to allow another user to harvest 
	 * fee is the amount paid to harvester
     */
    function deposit(uint256 _amount, address _poolInto, uint256 _threshold, uint256 _fee) external payable nonReentrant {
        require(msg.value == _amount && _amount > 0, "invalid amount");
		require(_fee <= 250, "maximum 2.5%!");
        harvest();
        payable(address(this)).transfer(_amount);
		uint256 _debt = _amount * accDtxPerShare / 1e12;
        
        userInfo[msg.sender].push(
                UserInfo(_amount, _poolInto, _threshold, _fee, _debt)
            );

        emit Deposit(msg.sender, _amount, _poolInto, _threshold, _fee, _debt);
    }
	
    /**
     * Harvests into pool
     */
    function harvest() public {
		uint256 _pending = IMasterChef(masterchef).pendingDtx(poolID, address(this));
        IMasterChef(masterchef).withdraw(poolID, 0);
		accDtxPerShare+= _pending * 1e12  / address(this).balance;
    }

    /**
    *
    */
    function setAdmin() external {
        admin = IMasterChef(masterchef).owner();
        treasury = IMasterChef(masterchef).feeAddress();
    }

    /**
     * Withdraws all tokens
     */
    function withdraw(uint256 _stakeID, address _harvestInto) public nonReentrant {
        harvest();
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];
		uint256 userTokens = user.amount; 

		uint256 currentAmount = userTokens * accDtxPerShare / 1e12 - user.debt;
		
		_removeStake(msg.sender, _stakeID);

        uint256 _toWithdraw;      

        if(_harvestInto == msg.sender) { 
            _toWithdraw = currentAmount * defaultDirectPayout / 10000;
            currentAmount = currentAmount - _toWithdraw;
            token.safeTransfer(msg.sender, _toWithdraw);
         } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = currentAmount * poolPayout[_harvestInto].amount / 10000;
            currentAmount = currentAmount - _toWithdraw;
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }
        token.safeTransfer(treasury, currentAmount); //penalty goes to governing contract
		
		emit Withdraw(msg.sender, _stakeID, _toWithdraw, currentAmount);

		payable(msg.sender).transfer(userTokens);
    } 



	//copy+paste of the previous function, can harvest custom stake ID
	//In case user has too many stakes, or if some are not worth harvesting
	function selfHarvest(uint256[] calldata _stakeID, address _harvestInto) external {
        require(_stakeID.length <= userInfo[msg.sender].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[msg.sender];
        harvest();
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;
 
        for(uint256 i = 0; i<_stakeID.length; i++) {
            _toWithdraw = user[_stakeID[i]].amount * accDtxPerShare / 1e12 - user[_stakeID[i]].debt;
			user[_stakeID[i]].debt = user[_stakeID[i]].amount * accDtxPerShare / 1e12;
			
			if(_harvestInto == msg.sender) {
            _payout = _toWithdraw * defaultDirectPayout / 10000;
            token.safeTransfer(msg.sender, _payout); 
			} else {
				require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
				_payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
				IacPool(_harvestInto).giftDeposit(_payout, msg.sender, poolPayout[_harvestInto].minServe);
			}

			uint256 _penalty = _toWithdraw - _payout;
			token.safeTransfer(treasury, _penalty); //penalty to treasury

			emit SelfHarvest(msg.sender, _stakeID[i], _harvestInto, _payout, _penalty);
        }        
    }


	//copy+paste of the previous function, can harvest custom stake ID
	//In case user has too many stakes, or if some are not worth harvesting
	function proxyHarvest(address _beneficiary, uint256[] calldata _stakeID) public {
        require(_stakeID.length <= userInfo[_beneficiary].length, "incorrect Stake list");
        UserInfo[] storage user = userInfo[_beneficiary];
        harvest();
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;
        address _harvestInto;
        uint256 _minThreshold;
        uint256 _callFee;

        for(uint256 i = 0; i<_stakeID.length; i++) {
			 _harvestInto = user[_stakeID[i]].pool;
			 _callFee = user[_stakeID[i]].feeToPay;
			 _minThreshold = user[_stakeID[i]].harvestThreshold;
			 
            _toWithdraw = user[_stakeID[i]].amount * accDtxPerShare / 1e12 - user[_stakeID[i]].debt;
			user[_stakeID[i]].debt = user[_stakeID[i]].amount * accDtxPerShare / 1e12;
			
			if(_harvestInto == _beneficiary) {
				//fee paid to harvester
				_payout = _toWithdraw * defaultDirectPayout / 10000;
				_callFee = _payout * _callFee / 10000;
				token.safeTransfer(msg.sender, _callFee); 
				token.safeTransfer(_beneficiary, (_payout - _callFee)); 
			} else {
				_payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
				require(_payout > _minThreshold, "minimum threshold not met");
				_callFee = _payout * _callFee / 10000;
				token.safeTransfer(msg.sender, _callFee); 
				IacPool(_harvestInto).giftDeposit((_payout - _callFee), _beneficiary, poolPayout[_harvestInto].minServe);
			}
			uint256 _penalty = _toWithdraw - _payout;
			token.safeTransfer(treasury, _penalty); //penalty to treasury
			
			emit Harvest(msg.sender, _beneficiary, _stakeID[i], _harvestInto, _payout, _penalty, _callFee);
        }
    }
	
	function massProxyHarvest(address[] calldata _beneficiary, uint256[][] calldata _stakeID) external {
		for(uint256 i = 0; i<_beneficiary.length; i++) {
			proxyHarvest(_beneficiary[i], _stakeID[i]);
		}
	}
	

    function viewStakeEarnings(address _user, uint256 _stakeID) external view returns (uint256) {
		UserInfo storage _stake = userInfo[_user][_stakeID];
        uint256 _pending = _stake.amount * virtualAccDtxPerShare() / 1e12 - _stake.debt;
        return _pending;
    }

    function viewUserTotalEarnings(address _user) external view returns (uint256) {
        UserInfo[] storage _stake = userInfo[_user];
        uint256 nrOfUserStakes = _stake.length;

		uint256 _totalPending = 0;
		
		for(uint256 i=0; i < nrOfUserStakes; i++) {
			_totalPending+= _stake[i].amount * virtualAccDtxPerShare() / 1e12 - _stake[i].debt;
		}
		
		return _totalPending;
    }
	//we want user deposit, we want total deposited, we want pending rewards, 
	function multiCall(address _user, uint256 _stakeID) external view returns(uint256, uint256, uint256) {
		UserInfo storage user = userInfo[_user][_stakeID];
		uint256 _pending = user.amount * virtualAccDtxPerShare() / 1e12 - user.debt;
		return(user.amount, address(this).balance, _pending);
	}

	// emergency withdraw, without caring about rewards
	function emergencyWithdraw(uint256 _stakeID) public {
		require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
		UserInfo storage user = userInfo[msg.sender][_stakeID];
		uint256 _amount = user.amount;
		
		_removeStake(msg.sender, _stakeID); //delete the stake
        emit Withdraw(msg.sender, _stakeID, 0, _amount);
		payable(msg.sender).transfer(_amount);
	}
	// withdraw all without caring about rewards
	// self-harvest to harvest rewards, then emergency withdraw all(easiest to withdraw all+earnings)
	// (non-rentrant in regular withdraw)
	function emergencyWithdrawAll() external {
		uint256 _stakeID = userInfo[msg.sender].length;
		while(_stakeID > 0) {
			_stakeID--;
			emergencyWithdraw(_stakeID);
		}
	}

	// With "Virtual harvest" for external calls
	function virtualAccDtxPerShare() public view returns (uint256) {
		uint256 _pending = IMasterChef(masterchef).pendingDtx(poolID, address(this));
		return (accDtxPerShare + _pending * 1e12  / address(this).balance);
	}

    //need to set pools before launch or perhaps during contract launch
    //determines the payout depending on the pool. could set a governance process for it(determining amounts for pools)
	//allocation contract contains the decentralized proccess for updating setting, but so does the admin(governor)
    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external {
        require(msg.sender == admin, "must be set by allocation contract or admin");
		if(_poolAddress == address(0)) {
			require(_amount <= 10000, "out of range");
			defaultDirectPayout = _amount;
		} else {
			require(_amount <= 10000, "out of range"); 
			poolPayout[_poolAddress].amount = _amount;
        	poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
		}
    }
    
    function updateSettings(uint256 _defaultDirectHarvest) external adminOnly {
        defaultDirectPayout = _defaultDirectHarvest;
    }


    /**
     * Returns number of stakes for a user
     */
    function getNrOfStakes(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingDtx(poolID, address(this)));
    }
	

	//public lookup for UI
    function publicBalanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID, address(this)); 
        return token.balanceOf(address(this)) + amount; 
    }
	
	/*
	 * Unlikely, but Masterchef can be changed if needed to be used without changing pools
	 * masterchef = IMasterChef(token.owner());
	 * Must stop earning first(withdraw tokens from old chef)
	*/
	function setMasterChefAddress(IMasterChef _masterchef, uint256 _newPoolID) external adminOnly {
		masterchef = _masterchef;
		poolID = _newPoolID; //in case pool ID changes
		
		uint256 _dummyAllowance = IERC20(dummyToken).allowance(address(this), address(masterchef));
		if(_dummyAllowance == 0) {
			IERC20(dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		}
	}
	
    /**
     * When contract is launched, dummyToken shall be deposited to start earning rewards
     */
    function startEarning() external adminOnly {
		IMasterChef(masterchef).deposit(poolID, dummyToken.balanceOf(address(this)));
    }
	
    /**
     * Dummy token can be withdrawn if ever needed(allows for flexibility)
     */
	function stopEarning(uint256 _withdrawAmount) external adminOnly {
		if(_withdrawAmount == 0) { 
			IMasterChef(masterchef).withdraw(poolID, dummyToken.balanceOf(address(masterchef)));
		} else {
			IMasterChef(masterchef).withdraw(poolID, _withdrawAmount);
		}
	}
	
    /**
     * Withdraws dummyToken to owner(who can burn it if needed)
     */
    function withdrawDummy(uint256 _amount) external adminOnly {	
        if(_amount == 0) { 
			dummyToken.safeTransfer(admin, dummyToken.balanceOf(address(this)));
		} else {
			dummyToken.safeTransfer(admin, _amount);
		}
    }
	
	
	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external {
		require(_tokenAddress != address(token), "illegal token");
		require(_tokenAddress != address(dummyToken), "illegal token");
		require(_tokenAddress != address(0) && _tokenAddress != 0x0000000000000000000000000000000000001010, "illegal token");
		
		IERC20(_tokenAddress).safeTransfer(IGovernor(admin).treasuryWallet(), IERC20(_tokenAddress).balanceOf(address(this)));
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
