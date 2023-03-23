// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface IMasterChef {
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
    event UpdateEmissions(address indexed user, uint256 newEmissions);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function DTXPerBlock() external view returns (uint256);

    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function dev(address _devaddr) external;

    function devaddr() external view returns (address);

    function dtx() external view returns (address);

    function emergencyWithdraw(uint256 _pid) external;

    function feeAddress() external view returns (address);

    function governorFee() external view returns (uint256);

    function isSpecialPool(address) external view returns (bool);
    
    function credit(address) external view returns (uint256);

    function massUpdatePools() external;

    function owner() external view returns (address);

    function pendingDtx(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function poolExistence(address) external view returns (bool);

    function poolInfo(uint256)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accDtxPerShare,
            uint16 depositFeeBP
        );

    function poolLength() external view returns (uint256);

    function renounceOwnership() external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external;

    function setFeeAddress(address _feeAddress) external;

    function setGovernorFee(uint256 _amount) external;

    function startBlock() external view returns (uint256);

    function tokenChangeOwnership(address _newOwner) external;

    function totalAllocPoint() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updateEmissionRate(uint256 _DTXPerBlock) external;

    function updatePool(uint256 _pid) external;

    function updateStartBlock(uint256 _startBlock) external;

    function userInfo(uint256, address)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);

    function withdraw(uint256 _pid, uint256 _amount) external;
    
    function publishTokens(address _to, uint256 _amount) external;
    
    function transferCredit(address _to, uint256 _amount) external;
}
