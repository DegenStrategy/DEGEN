// SPDX-License-Identifier: NONE
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IDTX.sol";


contract DTXChef is Ownable, ReentrancyGuard {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;
	
    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of DTX
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDtxPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDtxPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DTXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DTXs distribution occurs.
        uint256 accDtxPerShare;   // Accumulated DTX per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The DTX TOKEN!
    IDTX public dtx;
    // Dev address.
    address public devaddr;
	//portion of inflation goes to the decentralized governance contract
	uint256 public governorFee = 618; //6.18%
    // DTX tokens created per block.
    uint256 public DTXPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
	// User Credit (can publish such amount of tokens)
	mapping(address => uint256) public credit;
	// Does Pool Already Exist?
	mapping(IERC20 => bool) public poolExistence;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DTX mining starts.
    uint256 public startBlock;
	
	 // can burn tokens without allowance
	mapping(address => bool) public trustedContract;
	//makes it easier to verify(without event logs)
	uint256 public trustedContractCount; 

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event UpdateEmissions(address indexed user, uint256 newEmissions);
	event TrustedContract(address contractAddress, bool setting);
	event TransferCredit(address from, address to, uint256 amount);

    constructor(
        IDTX _DTX,
        address _devaddr,
        address _feeAddress,
        uint256 _DTXPerBlock,
        uint256 _startBlock
    ) {
        dtx = _DTX;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        DTXPerBlock = _DTXPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
	
	function publishTokens(address _to, uint256 _amount) external {
		credit[msg.sender] = credit[msg.sender] - _amount;
		dtx.mint(_to, _amount);
	}
	
	function burn(address _from, uint256 _amount) external returns (bool) {
		require(trustedContract[msg.sender], "only trusted contracts");
		require(dtx.burnToken(_from, _amount), "burn failed");
		credit[msg.sender] = credit[msg.sender] + _amount;
		return true;
	}
	
    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
		//prevents adding a contract that is not a token/LPtoken(incompatitible)
		require(_lpToken.balanceOf(address(this)) >= 0, "incompatitible token contract");
		//prevents same LP token from being added twice
		require(!poolExistence[_lpToken], "LP pool already exists");
		
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
		poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accDtxPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's DTX allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }


    // View function to see pending DTXs on frontend.
    function pendingDtx(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDtxPerShare = pool.accDtxPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accDtxPerShare = accDtxPerShare.add(dtxReward).mul(1e12).div(lpSupply);
        }
        return user.amount.mul(accDtxPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        dtx.mint(devaddr, dtxReward.mul(governorFee).div(10000));
        pool.accDtxPerShare = pool.accDtxPerShare.add(dtxReward).mul(1e12).div(lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for DTX allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDtxPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
				credit[msg.sender]+= pending;
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accDtxPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDtxPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
			credit[msg.sender]+= pending;
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDtxPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }
	
	// In case pools are changed (on migration old contract transfers it's credit to the new one)
	function transferCredit(address _to, uint256 _amount) external {
		require(trustedContract[msg.sender], "only trusted contracts");
		credit[msg.sender] = credit[msg.sender] - _amount;
		credit[_to] = credit[_to] + _amount;
		emit TransferCredit(msg.sender, _to, _amount);
	}
	
	//only owner can set trusted Contracts
	function setTrustedContract(address _contractAddress, bool _setting) external onlyOwner {
		if(trustedContract[_contractAddress] != _setting) { 
			trustedContract[_contractAddress] = _setting;
			_setting ? trustedContractCount++ : trustedContractCount--;
			emit TrustedContract(_contractAddress, _setting);
		}
	}

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

	function setGovernorFee(uint256 _amount) public onlyOwner {
		require(_amount <= 1000 && _amount >= 0);
		governorFee = _amount;
	}

    // Update dev address by the previous dev.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _DTXPerBlock) public onlyOwner {
        massUpdatePools();
        DTXPerBlock = _DTXPerBlock;
		
		emit UpdateEmissions(tx.origin, _DTXPerBlock);
    }

    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        require(block.number < startBlock, "already started");
		startBlock = _startBlock;
    }
	
	//For flexibility(can transfer to new masterchef if need be!)
	function tokenChangeOwnership(address _newOwner) external onlyOwner {
		dtx.transferOwnership(_newOwner);
	}
}
