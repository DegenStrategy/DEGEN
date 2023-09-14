// SPDX-License-Identifier: NONE
pragma solidity >=0.7.0 <0.9.0;

interface IMasterChef {
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event TransferCredit(address from, address to, uint256 amount);
    event TrustedContract(address contractAddress, bool setting);
    event UpdateEmissions(address indexed user, uint256 newEmissions);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function DTXPerBlock() external view returns (uint256);

    function add(
        uint256 _allocPoint,
        address _participant,
        bool _withUpdate
    ) external;

    function burn(address _from, uint256 _amount) external returns (bool);

    function credit(address) external view returns (uint256);

    function dev(address _devaddr) external;

    function devaddr() external view returns (address);

    function dtx() external view returns (address);

    function existingParticipant(address) external view returns (bool);

    function feeAddress() external view returns (address);

    function governorFee() external view returns (uint256);

    function massAdd(
        uint256[] memory _allocPoint,
        address[] memory _participant,
        bool[] memory _withUpdate
    ) external;

    function massUpdatePools() external;

    function owner() external view returns (address);

    function pendingDtx(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            uint256 allocPoint,
            uint256 lastRewardBlock,
            address participant
        );

    function poolLength() external view returns (uint256);

    function publishTokens(address _to, uint256 _amount) external;

    function renounceOwnership() external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external;

    function setFeeAddress(address _feeAddress) external;

    function setGovernorFee(uint256 _amount) external;

    function setTrustedContract(address _contractAddress, bool _setting)
        external;

    function startBlock() external view returns (uint256);

    function startPublishing(
        uint256 _pid,
        address _participant,
        uint256 _alloc
    ) external;

    function stopPublishing(uint256 _pid) external;

    function tokenChangeOwnership(address _newOwner) external;

    function totalAllocPoint() external view returns (uint256);

    function transferCredit(address _to, uint256 _amount) external;

    function transferOwnership(address newOwner) external;

    function trustedContract(address) external view returns (bool);

    function trustedContractCount() external view returns (uint256);

    function updateEmissionRate(uint256 _DTXPerBlock) external;

    function updatePool(uint256 _pid) external;

    function updateStartBlock(uint256 _startBlock) external;

    function totalTokensGranted() external view returns (uint256) {
}
