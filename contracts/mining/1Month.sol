// SPDX-License-Identifier: NONE

pragma solidity >= 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interface/IDTX.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";


/**
 * DTX time-locked deposit
 * Auto-compounding pool(1Month Deposit)
 * !!! Warning: !!! Copyrighted. 
 */
contract TimeDeposit is ReentrancyGuard {
    using SafeMath for uint256;

    struct UserInfo {
        uint256 shares; // number of shares for a user
        uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
        uint256 dtxAtLastUserAction; // keeps track of DTX deposited at the last user action
        uint256 lastUserActionTime; // keeps track of the last user action time
        uint256 mandatoryTimeToServe; // optional: disables early withdraw
    }
	//allows stakes to be transferred, similar to token transfers
	struct StakeTransfer {
		uint256 shares; // ALLOWANCE of shares
        uint256 lastDepositedTime;
        uint256 mandatoryTimeToServe;
	}

    IDTX public immutable token; // DTX token

    IMasterChef public masterchef;  
    
    uint256 public immutable withdrawFeePeriod = 30 days; // roughly 1 month
    uint256 public immutable gracePeriod = 3 days;

    mapping(address => UserInfo[]) public userInfo;
    mapping(address => uint256) public userVote; //the ID the user is voting for
    mapping(uint256 => uint256) public totalVotesForID; //total votes for a given ID
	mapping(address => address) public userDelegate; //user can delegate their voting to another wallet
	
	mapping(address => bool) public trustedSender; //Pools with shorter lockup duration(trustedSender(contracts) can transfer into this pool)
	mapping(address => bool) public trustedPool; //Pools with longer lockup duration(can transfer from this pool into trustedPool(contracts))
	
	mapping(address => mapping(address => StakeTransfer[])) private _stakeAllowances; 
	//similar to token allowances, difference being it's not for amount of tokens, but for a specific stake defined by shares, latdeposittime and mandatorytime

	uint256 public poolID; 
    uint256 public totalShares;
    address public admin; //admin = governing contract!
    address public treasury; //penalties go to this address
    address public migrationPool; //if pools are to change
	
	uint256 public minimumGift = 0;
	bool public updateMinGiftGovernor = true; //allows automatic update by anybody to costToVote from governing contract
    
    uint256 public callFee = 0; // call fee paid for rebalancing pools
	
	bool public allowStakeTransfer = true; //enable/disable transferring of stakes to another wallet
	bool public allowStakeTransferFrom = false; //allow third party transfers(disabled initially)
	
	bool public partialWithdrawals = true; //partial withdrawals from stakes
	bool public partialTransfers = true; //allows transferring a portion of  a stake
	
	bool public allowOrigin = true; //(dis)allows tx.origin for voting
	//safe to use tx.origin IMO. Can be disabled and use msg.sender instead
	//it allows the voting and delegating in a single transaction for all pools through a proxy contract
	
	// Easier to verify (opposed to checking event logs)
	uint256 public trustedSenderCount;
	uint256 public trustedPoolCount;

    event Deposit(address indexed sender, uint256 amount, uint256 shares, uint256 lastDepositedTime);
    event GiftDeposit(
        address indexed sender, 
        address indexed recipient, 
        uint256 amount, 
        uint256 shares, 
        uint256 lastDepositedTime
    );
    event AddAndExtendStake(
        address indexed sender, 
        address indexed recipient, 
        uint256 amount, 
        uint256 stakeID, 
        uint256 shares, 
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount, uint256 penalty, uint256 shares);
    
	event TransferStake(address indexed sender, address indexed recipient, uint256 shares, uint256 stakeID);
    event HopPool(address indexed sender, uint256 DTXamount, uint256 shares, address indexed newPool);
    event MigrateStake(address indexed goodSamaritan, uint256 DTXamount, uint256 shares, address indexed recipient);
   
    event HopDeposit(
        address indexed recipient, 
        uint256 amount, 
        uint256 shares, 
        uint256 previousLastDepositedTime, 
        uint256 mandatoryTime
    );
	
    event RemoveVotes(address indexed voter, uint256 proposalID, uint256 change);
    event AddVotes(address indexed voter, uint256 proposalID, uint256 change);
	
	event TrustedSender(address contractAddress, bool setting);
	event TrustedPool(address contractAddress, bool setting);
	
	event StakeApproval(
        address owner, 
        address spender, 
        uint256 allowanceID, 
        uint256 shareAllowance, 
        uint256 lastDeposit, 
        uint256 mandatoryTime
    );
	event StakeAllowanceRevoke(address owner, address spender, uint256 allowanceID);
	event TransferStakeFrom(address _from, address _to, uint256 _stakeID, uint256 _allowanceID);
	
	event SetDelegate(address userDelegating, address delegatee);

   constructor(
    ) {
        token = IDTX();
        masterchef = IMasterChef();
        admin = msg.sender;
        poolID = 0;
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier decentralizedVoting() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }
	
    /**
     * @notice Deposits funds into the DTX time-locked vault
     * @param _amount: number of tokens to deposit (in DTX
     * 
     * Creates a NEW stake
     */
    function deposit(uint256 _amount) external nonReentrant {
    	require(_amount > 0, "Nothing to deposit");
	
        uint256 pool = balanceOf();
        require(masterchef.burn(msg.sender, _amount), "token burn failed");
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        
        totalShares = totalShares.add(currentShares);
        
        userInfo[msg.sender].push(
                UserInfo(currentShares, block.timestamp, _amount, block.timestamp, 0)
            );
        
		uint256 votingFor = userVote[msg.sender];
        if(votingFor != 0) {
            _updateVotingAddDiff(msg.sender, votingFor, currentShares);
        }

        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    /**
     * Equivalent to Deposit
     * Instead of crediting the msg.sender, it credits custom recipient
     * A mechanism to gift a time-locked stake to another wallet
     * Users can withdraw at any time(but will pay a penalty)
     * Optionally stake can be irreversibly locked for a minimum period of time(minToServe)
     */
    function giftDeposit(uint256 _amount, address _toAddress, uint256 _minToServeInSecs) external nonReentrant {
        require(_amount >= minimumGift, "Below Minimum Gift");

        uint256 pool = balanceOf();
        require(masterchef.burn(msg.sender, _amount), "token burn failed");
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        
        totalShares = totalShares.add(currentShares);
        
        userInfo[_toAddress].push(
                UserInfo(currentShares, block.timestamp, _amount, block.timestamp, _minToServeInSecs)
            );
			
        uint256 votingFor = userVote[_toAddress];
        if(votingFor != 0) {
            _updateVotingAddDiff(_toAddress, votingFor, currentShares);
        }

        emit GiftDeposit(msg.sender, _toAddress, _amount, currentShares, block.timestamp);
    }
    
    /**
     * @notice Deposits funds into the DTX time-locked vault
     * @param _amount: number of tokens to deposit (in DTX
     * 
     * Deposits into existing stake, effectively extending the stake
     * It's used for rolling over stakes by the governor(admin) as well
     * Mandatory Lock Up period can only be Increased
	 * It can be Decreased if stake is being extended(after it matures)
     */
    function addAndExtendStake(address _recipientAddr, uint256 _amount, uint256 _stakeID, uint256 _lockUpTokensInSeconds) external nonReentrant {
        require(_amount > 0, "Nothing to deposit");
        require(userInfo[_recipientAddr].length > _stakeID, "wrong Stake ID");
        
        if(msg.sender != admin) { require(_recipientAddr == msg.sender, "can only extend your own stake"); }

        uint256 pool = balanceOf();
        require(masterchef.burn(msg.sender, _amount), "token burn failed");
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        UserInfo storage user = userInfo[_recipientAddr][_stakeID];

        user.shares = user.shares.add(currentShares);
        totalShares = totalShares.add(currentShares);
        
        if(_lockUpTokensInSeconds > user.mandatoryTimeToServe || 
				block.timestamp > user.lastDepositedTime.add(withdrawFeePeriod)) { 
			user.mandatoryTimeToServe = _lockUpTokensInSeconds; 
		}
		
        user.dtxAtLastUserAction = user.shares.mul(balanceOf()).div(totalShares);
        user.lastUserActionTime = block.timestamp;
		user.lastDepositedTime = block.timestamp;
        
		uint256 votingFor = userVote[_recipientAddr];
        if(votingFor != 0) {
            _updateVotingAddDiff(_recipientAddr, votingFor, currentShares);
        }

        emit AddAndExtendStake(msg.sender, _recipientAddr, _amount, _stakeID, currentShares, block.timestamp);
    }
 

    function withdrawAll(uint256 _stakeID) external {
        withdraw(userInfo[msg.sender][_stakeID].shares, _stakeID);
    }

    
    /**
     * @notice Sets admin address and treasury
     * If new governor is set, anyone can pay the gas to update the addresses
	 * Masterchef owns the token, the governor owns the Masterchef
	 * Treasury is feeAddress from masterchef(which collects fees from deposits into masterchef)
	 * Currently all penalties are going to fee address(currently governing contract)
	 * Alternatively, fee address can be set as a separate contract, which would re-distribute
	 * The tokens back into pool(so honest stakers would directly receive penalties from prematurely ended stakes)
	 * Alternatively could also split: a portion to honest stakers, a portion into governing contract. 
	 * With initial setting, all penalties are going towards governing contract
     */
    function setAdmin() external {
        admin = IMasterChef(masterchef).owner();
        treasury = IMasterChef(masterchef).feeAddress();
    }
	
	//updates minimum gift to costToVote from Governing contract
	function updateMinimumGift() external {
		require(updateMinGiftGovernor, "automatic update disabled");
		minimumGift = IGovernor(admin).costToVote();
	}

    /**
     * @notice Withdraws from funds from the DTX time-locked vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares, uint256 _stakeID) public {
        require(_stakeID < userInfo[msg.sender].length, "invalid stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");
        require(block.timestamp > user.lastDepositedTime.add(user.mandatoryTimeToServe), "must serve mandatory time");
        if(!partialWithdrawals) { require(_shares == user.shares, "must transfer full stake"); }

        uint256 currentAmount = (balanceOf().mul(_shares)).div(totalShares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);

        uint256 currentWithdrawFee = 0;
        
        if (block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 withdrawFee = uint256(2500).sub(((block.timestamp.sub(user.lastDepositedTime)).div(86400)).mul(786).div(10));
            currentWithdrawFee = currentAmount.mul(withdrawFee).div(10000);
            IMasterChef(masterchef).publishTokens(treasury, currentWithdrawFee); 
            currentAmount = currentAmount.sub(currentWithdrawFee);
        } else if(block.timestamp > user.lastDepositedTime.add(withdrawFeePeriod).add(gracePeriod)) {
            uint256 withdrawFee = block.timestamp.sub(user.lastDepositedTime.add(withdrawFeePeriod)).div(86400).mul(786).div(10);
            if(withdrawFee > 2500) { withdrawFee = 2500; }
            currentWithdrawFee = currentAmount.mul(withdrawFee).div(10000);
            IMasterChef(masterchef).publishTokens(treasury, currentWithdrawFee);  
            currentAmount = currentAmount.sub(currentWithdrawFee);
        }

        if (user.shares > 0) {
            user.dtxAtLastUserAction = user.shares.mul(balanceOf().sub(currentAmount)).div(totalShares);
            user.lastUserActionTime = block.timestamp;
        } else {
            _removeStake(msg.sender, _stakeID); //delete the stake
        }
        
		uint256 votingFor = userVote[msg.sender];
        if(votingFor != 0) {
            _updateVotingSubDiff(msg.sender, votingFor, _shares);
        }

		emit Withdraw(msg.sender, currentAmount, currentWithdrawFee, _shares);
		
		IMasterChef(masterchef).publishTokens(msg.sender, currentAmount);
    } 
    
    /**
     * Users can transfer their stake to another pool
     * Can only transfer to pool with longer lock-up period(trusted pools)
     * Equivalent to withdrawing, but it deposits the stake into another pool as hopDeposit
     * Users can transfer stake without penalty
     * Time served gets transferred 
     * The pool is "registered" as a "trustedSender" to another pool
     */
    function hopStakeToAnotherPool(uint256 _shares, uint256 _stakeID, address _poolAddress) public {
        require(_shares > 0, "Nothing to withdraw");
		require(_stakeID < userInfo[msg.sender].length, "wrong stake ID");
		
        UserInfo storage user = userInfo[msg.sender][_stakeID];
		require(_shares <= user.shares, "Withdraw amount exceeds balance");
        if(!partialWithdrawals) { require(_shares == user.shares, "must transfer full stake"); } 
        
		uint256 _lastDepositedTime = user.lastDepositedTime;
        if(trustedPool[_poolAddress]) { 
			if(block.timestamp > _lastDepositedTime.add(withdrawFeePeriod).add(gracePeriod)) {
				_lastDepositedTime = block.timestamp; //if after grace period, resets timer
			}
        } else { 
			//can only hop into trusted Pools or into trusted sender(lower pool) after time has been served within grace period
			//only meant for stakeRollover. After hop, stake is extended and timer reset
            require(trustedSender[_poolAddress] && block.timestamp > _lastDepositedTime.add(withdrawFeePeriod) &&
                                block.timestamp < _lastDepositedTime.add(withdrawFeePeriod).add(gracePeriod),
                                        "can only hop into pre-set Pools");
		}

        uint256 currentAmount = (balanceOf().mul(_shares)).div(totalShares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);
		
		uint256 votingFor = userVote[msg.sender];
        if(votingFor != 0) {
            _updateVotingSubDiff(msg.sender, votingFor, _shares);
        }
		
		IacPool(_poolAddress).hopDeposit(currentAmount, msg.sender, _lastDepositedTime, user.mandatoryTimeToServe);
		IMasterChef(masterchef).transferCredit(_poolAddress, currentAmount);

        if (user.shares > 0) {
            user.dtxAtLastUserAction = user.shares.mul(balanceOf()).div(totalShares);
            user.lastUserActionTime = block.timestamp;
        } else {
            _removeStake(msg.sender, _stakeID); //delete the stake
        }
        
        emit HopPool(msg.sender, currentAmount, _shares, _poolAddress);
    }

    
    /**
     * hopDeposit is equivalent to gift deposit, exception being that the time served can be passed
     * The msg.sender can only be a trusted contract
     * The checks are already made in the hopStakeToAnotherPool function
     * msg sender can only be trusted senders
     */
     
    function hopDeposit(uint256 _amount, address _recipientAddress, uint256 previousLastDepositedTime, uint256 _mandatoryTime) external {
        require(trustedSender[msg.sender] || trustedPool[msg.sender], "only trusted senders(other pools)");
		//only trustedSenders allowed. TrustedPools are under condition that the stake has matured(hopStake checks condition)
        
        uint256 pool = balanceOf();
		
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        
        totalShares = totalShares.add(currentShares);
        
        userInfo[_recipientAddress].push(
                UserInfo(currentShares, previousLastDepositedTime, _amount,
                    block.timestamp, _mandatoryTime)
            );

		uint256 votingFor = userVote[_recipientAddress];
        if(votingFor != 0) {
            _updateVotingAddDiff(_recipientAddress, votingFor, currentShares);
        }

        emit HopDeposit(_recipientAddress, _amount, currentShares, previousLastDepositedTime, _mandatoryTime);
    }
	
    /**
     * Users are encouraged to keep staking
     * Governor pays bonuses to re-commit and roll over your stake
     * Higher bonuses available for hopping into pools with longer lockup period
     */
    function stakeRollover(address _poolInto, uint256 _stakeID) external {
        require(userInfo[msg.sender].length > _stakeID, "invalid stake ID");
        
        UserInfo storage user = userInfo[msg.sender][_stakeID];
        
        require(block.timestamp > user.lastDepositedTime.add(withdrawFeePeriod), "stake not yet mature");
        
        uint256 currentAmount = (balanceOf().mul(user.shares)).div(totalShares); 
        uint256 toPay = currentAmount.mul(IGovernor(admin).getRollBonus(_poolInto)).div(10000);

        require(IDTX(token).balanceOf(admin) >= toPay, "governor reserves are currently insufficient");
        
        if(_poolInto == address(this)) {
            IGovernor(admin).stakeRolloverBonus(msg.sender, _poolInto, toPay, _stakeID); //gov sends tokens to extend the stake
        } else {
			hopStakeToAnotherPool(user.shares, _stakeID, _poolInto); //will revert if pool is wrong
			IGovernor(admin).stakeRolloverBonus(msg.sender, _poolInto, toPay, IacPool(_poolInto).getNrOfStakes(msg.sender) - 1); //extends latest stake
        }
    }
    
    /**
     * Transfer stake to another account(another wallet address)
     */
    function transferStakeToAnotherWallet(uint256 _shares, uint256 _stakeID, address _recipientAddress) external {
        require(allowStakeTransfer, "transfers disabled");
		require(_recipientAddress != msg.sender, "can't transfer to self");
        require(_stakeID < userInfo[msg.sender].length, "wrong stake ID");
        UserInfo storage user = userInfo[msg.sender][_stakeID];
		uint256 _tokensTransferred = _shares.mul(balanceOf()).div(totalShares);
        require(_tokensTransferred >= minimumGift, "Below minimum threshold");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");
        if(!partialTransfers) { require(_shares == user.shares, "must transfer full stake"); }
        
        user.shares = user.shares.sub(_shares);

		uint256 votingFor = userVote[msg.sender];
        if(votingFor != 0) {
            _updateVotingSubDiff(msg.sender, votingFor, _shares);
        }
		votingFor = userVote[_recipientAddress];
        if(votingFor != 0) {
            _updateVotingAddDiff(_recipientAddress, votingFor, _shares);
        }
        
        userInfo[_recipientAddress].push(
                UserInfo(_shares, user.lastDepositedTime, _tokensTransferred, block.timestamp, user.mandatoryTimeToServe)
            );

        if (user.shares > 0) {
            user.dtxAtLastUserAction = user.shares.mul(balanceOf()).div(totalShares);
            user.lastUserActionTime = block.timestamp;
        } else {
            _removeStake(msg.sender, _stakeID); //delete the stake
        }

        emit TransferStake(msg.sender, _recipientAddress, _shares, _stakeID);
    }

    /**
     * user delegates their shares to cast a vote on a proposal
     * casting to proposal ID = 0 is basically neutral position (not voting)
	 * Is origin is allowed, proxy contract can be used to vote in all pools in a single tx
	 * asProxy allows contracts to vote as well
     */
    function voteForProposal(uint256 proposalID, bool asProxy) external {
        address _wallet;
		(allowOrigin && asProxy) ? _wallet = tx.origin : _wallet = msg.sender;
        uint256 votingFor = userVote[_wallet]; //the ID the user is voting for(before change)
		
        if(proposalID != votingFor) { // do nothing if false(already voting for that ID)
	
			uint256 userTotalShares = getUserTotalShares(_wallet);
			if(userTotalShares > 0) { //if false, no shares, thus just assign proposal ID to userVote
				if(proposalID != 0) { // Allocates vote to an ID
					if(votingFor == 0) { //starts voting, adds votes
						_updateVotingAddDiff(_wallet, proposalID, userTotalShares);
					} else { //removes from previous vote, adds to new
						_updateVotingSubDiff(_wallet, votingFor, userTotalShares);
						_updateVotingAddDiff(_wallet, proposalID, userTotalShares);
					}
				} else { //stops voting (previously voted, now going into neutral (=0)
					_updateVotingSubDiff(_wallet, votingFor, userTotalShares);
				}
			}
			userVote[_wallet] = proposalID;
		}
    }
	
	/*
	* delegatee can vote with shares of another user
	*/
    function delegateeVote(address[] calldata votingAddress, uint256 proposalID) external {
        for(uint256 i = 0; i < votingAddress.length; i++) { 
			if(userDelegate[votingAddress[i]] == msg.sender) {
				uint256 votingFor = userVote[votingAddress[i]]; //the ID the user is voting for(before change)
				
				if(proposalID != votingFor){
				
					uint256 userTotalShares = getUserTotalShares(votingAddress[i]);
					if(userTotalShares > 0) {
						if(proposalID != 0) { 
							if(votingFor == 0) {
								_updateVotingAddDiff(votingAddress[i], proposalID, userTotalShares);
							} else {
								_updateVotingSubDiff(votingAddress[i], votingFor, userTotalShares);
								_updateVotingAddDiff(votingAddress[i], proposalID, userTotalShares);
							}
						} else {
							_updateVotingSubDiff(votingAddress[i], votingFor, userTotalShares);
						}
					}
					userVote[votingAddress[i]] = proposalID;
				}
			}
		}
    }
	
     /**
     * Users can delegate their shares
     */
    function setDelegate(address _delegate, bool asProxy) external {
        address _wallet;
		(allowOrigin && asProxy) ? _wallet=tx.origin : _wallet=msg.sender;
        userDelegate[_wallet] = _delegate;
        
		emit SetDelegate(_wallet, _delegate);
    }
	
	// allows third party stake transfer(stake IDs can be changed, 
	// so instead of being identified through ID, it's identified by shares, lastdeposit and mandatory time
    function giveStakeAllowance(address spender, uint256 _stakeID) external {
		UserInfo storage user = userInfo[msg.sender][_stakeID];
		require(user.shares.mul(balanceOf()).div(totalShares) >= minimumGift, "below minimum threshold");
		
		uint256 _allowanceID = _stakeAllowances[msg.sender][spender].length;

		_stakeAllowances[msg.sender][spender].push(
			StakeTransfer(user.shares, user.lastDepositedTime, user.mandatoryTimeToServe)
		);
		
		emit StakeApproval(msg.sender, spender, _allowanceID, user.shares, user.lastDepositedTime, user.mandatoryTimeToServe);
    }
	
    //Note: allowanceID (and not ID of the stake!)
	function revokeStakeAllowance(address spender, uint256 allowanceID) external {
		StakeTransfer[] storage allowances = _stakeAllowances[msg.sender][spender];
        uint256 lastAllowanceID = allowances.length.sub(1);
        
        if(allowanceID != lastAllowanceID) {
            allowances[allowanceID] = allowances[lastAllowanceID];
        }
        
        allowances.pop();
		
		emit StakeAllowanceRevoke(msg.sender, spender, allowanceID);
	}
	
    /**
     * A third party can transfer the stake(allowance required)
	 * Allows smart contract inter-operability similar to how regular tokens work
	 * Can only transfer full stake (You can split the stake through other methods)
	 * Bad: makes illiquid stakes liquid
	 * I think best is to have the option, but leave it unavailable unless desired
     */
    function transferStakeFrom(address _from, uint256 _stakeID, uint256 allowanceID, address _to) external returns (bool) {
        require(allowStakeTransferFrom, "third party stake transfers disabled");
		
		require(_from != _to, "can't transfer to self");
        require(_stakeID < userInfo[_from].length, "wrong stake ID");
        UserInfo storage user = userInfo[_from][_stakeID];
		
		(uint256 _shares, uint256 _lastDeposit, uint256 _mandatoryTime) = stakeAllowances(_from, msg.sender, allowanceID);

		//since stake ID can change, the stake to transfer is identified through number of shares, last deposit and mandatory time
		//checks if stake allowance(for allowanceID) matches the actual stake of a user
		require(_shares == user.shares, "incorrect stake or allowance");
		require(_lastDeposit == user.lastDepositedTime, "incorrect stake or allowance");
		require(_mandatoryTime == user.mandatoryTimeToServe, "incorrect stake or allowance");
     
		uint256 votingFor = userVote[_from];
        if(votingFor != 0) {
            _updateVotingSubDiff(_from, votingFor, _shares);
        }
		votingFor = userVote[_to];
        if(votingFor != 0) {
            _updateVotingAddDiff(_to, votingFor, _shares);
        }

        _removeStake(_from, _stakeID); //transfer from must transfer full stake
		_revokeStakeAllowance(_from, allowanceID);
		
        userInfo[_to].push(
                UserInfo(_shares, _lastDeposit, _shares.mul(balanceOf()).div(totalShares),
                    block.timestamp, _mandatoryTime)
            );

        emit TransferStakeFrom(_from, _to, _stakeID, allowanceID);
		
		return true;
    }

	
    /**
	 * Allows the pools to be changed to new contracts
     * if migration Pool is set
     * anyone can be a "good Samaritan"
     * and transfer the stake of another user to the new pool
     */
    function migrateStake(address _staker, uint256 _stakeID) public {
        require(migrationPool != address(0), "migration not activated");
        require(_stakeID < userInfo[_staker].length, "invalid stake ID");
        UserInfo storage user = userInfo[_staker][_stakeID];
		require(user.shares > 0, "no balance");
        
        uint256 currentAmount = (balanceOf().mul(user.shares)).div(totalShares);
        totalShares = totalShares.sub(user.shares);
		
        user.shares = 0; // equivalent to deleting the stake. Pools are no longer to be used,
						//setting user shares to 0 is sufficient
		
		IacPool(migrationPool).hopDeposit(currentAmount, _staker, user.lastDepositedTime, user.mandatoryTimeToServe);
		IMasterChef(masterchef).transferCredit(migrationPool, currentAmount);

        emit MigrateStake(msg.sender, currentAmount, user.shares, _staker);
    }

    /**
     * loop and migrate all user stakes
     * could run out of gas if too many stakes
     */
    function migrateAllStakes(address _staker) external {
        UserInfo[] storage user = userInfo[_staker];
        uint256 userStakes = user.length;
        
        for(uint256 i=0; i < userStakes; i++) {
            migrateStake(_staker, i);
        }
    }
    
	//enables or disables ability to draw stake from another wallet(allowance required)
	function enableDisableStakeTransferFrom(bool _setting) external decentralizedVoting {
		allowStakeTransferFrom = _setting;
	}

    /**
     * @notice Sets call fee 
     * @dev Only callable by the contract admin.
     */
    function setCallFee(uint256 _callFee) external decentralizedVoting {
        callFee = _callFee;
    }

     /*
     * set trusted senders, other pools that we can receive from (that can hopDeposit)
     * guaranteed to be trusted (they rely lastDepositTime)
     */
    function setTrustedSender(address[] calldata _sender, bool _setting) external decentralizedVoting {
        for(uint i=0; i < _sender.length; i++) {
		if(trustedSender[_sender[i]] != _setting) {
				trustedSender[_sender[i]] = _setting;

				_setting ? trustedSenderCount++ : trustedSenderCount--;

				emit TrustedSender(_sender[i], _setting);
			}
		}
    }
    
     /**
     * set trusted pools, the smart contracts that we can send the tokens to without penalty
	 * NOTICE: new pool must be set as trusted contract(to be able to draw balance without allowance)
     */
    function setTrustedPool(address[] calldata _pool, bool _setting) external decentralizedVoting {
        for(uint i=0; i < _pool.length; i++) {
		if(trustedPool[_pool[i]] != _setting) {
			trustedPool[_pool[i]] = _setting;
			
			_setting ? trustedPoolCount++ : trustedPoolCount--;

			emit TrustedPool(_pool[i], _setting);
		}
	}
    }


     /**
     * set address of new pool that we can migrate into
	 * !!! NOTICE !!!
     *  new pool must be set as trusted contract in the token contract by the governor(to be able to draw balance without allowance)
     */
    function setMigrationPool(address _newPool) external decentralizedVoting {
		migrationPool = _newPool;
    }
    
     /**
     * Enable or disable partial withdrawals from stakes
     */
    function modifyPartialWithdrawals(bool _decision) external decentralizedVoting {
        partialWithdrawals = _decision;
    }
	function modifyPartialTransfers(bool _decision) external decentralizedVoting {
        partialTransfers = _decision;
    }
	
	function enableDisableStakeTransfer(bool _setting) external decentralizedVoting {
		allowStakeTransfer = _setting;
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
	
	function allowTxOrigin(bool _setting) external decentralizedVoting {
		allowOrigin = _setting;
	}
	
	//sets minimum amount(for sending gift, transferring to another wallet,...)
	//if setting is enabled, minimumGift can be auto-updated to costToVote from governor by anybody
	function setMinimumGiftDeposit(uint256 _amount, bool _setting) external decentralizedVoting {
		minimumGift = _amount;
		updateMinGiftGovernor = _setting;
	}

	 /**
     * Returns number of stakes for a user
     */
    function getNrOfStakes(address _user) external view returns (uint256) {
        return userInfo[_user].length;
    }
	
    /**
     * @notice Calculates the expected harvest reward from third party
     * @return Expected reward to collect in DTX
     */
    function calculateHarvestDTXRewards() external view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID);
        uint256 currentCallFee = amount.mul(callFee).div(10000);

        return currentCallFee;
    }

    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID);

        return amount;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalShares == 0 ? 1e18 : balanceOf().mul(1e18).div(totalShares);
    }

	/**
     * Returns all shares for a user
     */
    function getUserTotalShares(address _user) public view returns (uint256) {
        UserInfo[] storage _stake = userInfo[_user];
        uint256 nrOfUserStakes = _stake.length;

		uint256 countShares = 0;
		
		for(uint256 i=0; i < nrOfUserStakes; i++) {
			countShares += _stake[i].shares;
		}
		
		return countShares;
    }
    
    /**
     * @notice returns number of shares for a certain stake of an user
     */
    function getUserShares(address _wallet, uint256 _stakeID) public view returns (uint256) {
        return userInfo[_wallet][_stakeID].shares;
    }
	
    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in MasterChef
     */
    function balanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID); 
		uint256 _credit = IMasterChef(masterchef).credit(address(this));
        return amount.add(_credit); 
    }

	function nrOfstakeAllowances(address owner, address spender) public view returns (uint256) {
        return _stakeAllowances[owner][spender].length;
    }
	
    function stakeAllowances(address owner, address spender, uint256 allowanceID) public view returns (uint256, uint256, uint256) {
        StakeTransfer storage stakeStore = _stakeAllowances[owner][spender][allowanceID];
        return (stakeStore.shares, stakeStore.lastDepositedTime, stakeStore.mandatoryTimeToServe);
    }
	
    //Note: allowanceID (and not ID of the stake!)
	function _revokeStakeAllowance(address owner, uint256 allowanceID) private {
		StakeTransfer[] storage allowances = _stakeAllowances[owner][msg.sender];
        uint256 lastAllowanceID = allowances.length.sub(1);
        
        if(allowanceID != lastAllowanceID) {
            allowances[allowanceID] = allowances[lastAllowanceID];
        }
        
        allowances.pop();
		
		emit StakeAllowanceRevoke(owner, msg.sender, allowanceID);
	}
	
    /**
     * updates votes(whenever there is transfer of funds)
     */
    function _updateVotingAddDiff(address voter, uint256 proposalID, uint256 diff) private {
        totalVotesForID[proposalID] = totalVotesForID[proposalID].add(diff);
        
        emit AddVotes(voter, proposalID, diff);
    }
    function _updateVotingSubDiff(address voter, uint256 proposalID, uint256 diff) private {
        totalVotesForID[proposalID] = totalVotesForID[proposalID].sub(diff);
        
        emit RemoveVotes(voter, proposalID, diff);
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
