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

    // Info of each pool.
    struct PoolInfo {       // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DTXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DTXs distribution occurs.
        address participant;   // participating contract    
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
	// User Credit (can publish such amount of tokens)
	mapping(address => uint256) public credit;
	// Does Pool Already Exist?
	mapping(address => bool) public existingParticipant;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DTX mining starts.
    uint256 public startBlock;
	
	 // can burn tokens without allowance
	mapping(address => bool) public trustedContract;
	//makes it easier to verify(without event logs)
	uint256 public trustedContractCount; 

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
        uint256 _startBlock,
	address _airdropLocked,
	uint256 _airdropLockedAmount,
	address _airdropFull,
	uint256 _airdropFullAmount,
    ) {
        dtx = _DTX;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        DTXPerBlock = _DTXPerBlock;
        startBlock = _startBlock;
	credit[_airdropLocked] = _airdropLockedAmount;
	credit[_airdropFull] = _airdropFullAmount;
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
    function add(uint256 _allocPoint, address _participant, bool _withUpdate) public onlyOwner {
		require(!existingParticipant[_participant], "contract already participating");
		
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
		existingParticipant[_participant] = true;
        poolInfo.push(PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            participant: _participant
        }));
    }
    
    function massAdd(uint256[] calldata _allocPoint, address[] calldata _participant, bool[] calldata _withUpdate) external {
        require(_allocPoint.length == _participant.length && _allocPoint.length == _withUpdate.length);
        for(uint i=0; i < _allocPoint.length; i++) {
            add(_allocPoint[i], _participant[i], _withUpdate[i]);
        }
    }

    // Update the given pool's DTX allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    // View function to see pending DTXs on frontend.
    function pendingDtx(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock && pool.participant != address(0)) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            return dtxReward;
        }
        return 0;
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
        if (pool.participant == address(0) || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        dtx.mint(devaddr, dtxReward.mul(governorFee).div(10000));
		credit[pool.participant] = credit[pool.participant] + dtxReward;
        pool.lastRewardBlock = block.number;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.participant == msg.sender, "withdraw: not good");
        updatePool(_pid);
        if(_amount > 0) {
            pool.participant = address(0);
            pool.allocPoint = 0;
            totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function stopPublishing(uint256 _pid) external onlyOwner {
        updatePool(_pid);
        poolInfo[_pid].participant = address(0);
        poolInfo[_pid].allocPoint = 0;
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint);
    }

	function startPublishing(uint256 _pid, address _participant, uint256 _alloc) external onlyOwner {
		require(poolInfo[_pid].allocPoint == 0 && poolInfo[_pid].participant == address(0), "already earning");
        updatePool(_pid);
        poolInfo[_pid].participant = _participant;
        poolInfo[_pid].allocPoint = _alloc;
        totalAllocPoint = totalAllocPoint.add(_alloc);
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
	require(_startBlock > startBlock, "can only delay");
		startBlock = _startBlock;
    }
	
	//For flexibility(can transfer to new masterchef if need be!)
	function tokenChangeOwnership(address _newOwner) external onlyOwner {
		dtx.transferOwnership(_newOwner);
	}
}
