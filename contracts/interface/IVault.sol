interface IVault {
    event CollectedFee(address ref, uint256 amount);
    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 debt,
        uint256 depositFee,
        address referral
    );
    event Harvest(
        address indexed harvester,
        address indexed benficiary,
        uint256 stakeID,
        address harvestInto,
        uint256 harvestAmount,
        uint256 penalty,
        uint256 callFee
    );
    event SelfHarvest(
        address indexed user,
        address harvestInto,
        uint256 harvestAmount,
        uint256 penalty
    );
    event UserSettingUpdate(
        address indexed user,
        address poolAddress,
        uint256 threshold,
        uint256 feeToPay
    );
    event Withdraw(
        address indexed sender,
        uint256 stakeID,
        uint256 harvestAmount,
        uint256 penalty
    );

    function accDtxPerShare() external view returns (uint256);

    function admin() external view returns (address);

    function calculateTotalPendingDTXRewards() external view returns (uint256);

    function collectCommission(
        address[] memory _beneficiary,
        uint256[][] memory _stakeID
    ) external;

    function collectCommissionAuto(address[] memory _beneficiary) external;

    function defaultDirectPayout() external view returns (uint256);

    function deposit(uint256 _amount, address referral) external payable;

    function depositFee() external view returns (uint256);

    function dummyToken() external view returns (address);

    function emergencyWithdraw(uint256 _stakeID) external;

    function emergencyWithdrawAll() external;

    function fundingRate() external view returns (uint256);

    function getNrOfStakes(address _user) external view returns (uint256);

    function harvest() external;

    function masterchef() external view returns (address);

    function maxFee() external view returns (uint256);

    function maxFundingFee() external view returns (uint256);

    function multiCall(address _user, uint256 _stakeID)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function poolID() external view returns (uint256);

    function poolPayout(address)
        external
        view
        returns (uint256 amount, uint256 minServe);

    function publicBalanceOf() external view returns (uint256);

    function refShare1() external view returns (uint256);

    function refShare2() external view returns (uint256);

    function selfHarvest(uint256[] memory _stakeID, address _harvestInto)
        external;

    function setAdmin() external;

    function setDepositFee(uint256 _depositFee) external;

    function setFundingRate(uint256 _fundingRate) external;

    function setMasterChefAddress(address _masterchef, uint256 _newPoolID)
        external;

    function setPoolPayout(
        address _poolAddress,
        uint256 _amount,
        uint256 _minServe
    ) external;

    function setRefShare1(uint256 _refShare1) external;

    function setRefShare2(uint256 _refShare2) external;

    function setTreasury(address _newTreasury) external;

    function startEarning() external;

    function stopEarning(uint256 _withdrawAmount) external;

    function token() external view returns (address);

    function treasury() external view returns (address);

    function updateSettings(uint256 _defaultDirectHarvest) external;

    function userInfo(address, uint256)
        external
        view
        returns (
            uint256 amount,
            uint256 debt,
            uint256 feesPaid,
            address referredBy,
            uint256 lastAction
        );

    function viewStakeEarnings(address _user, uint256 _stakeID)
        external
        view
        returns (uint256);

    function viewUserTotalEarnings(address _user)
        external
        view
        returns (uint256);

    function virtualAccDtxPerShare() external view returns (uint256);

    function withdraw(uint256 _stakeID, address _harvestInto) external;

    function withdrawDummy(uint256 _amount) external;

    function referralPoints(address) external view returns (uint256);

    function withdrawStuckTokens(address _tokenAddress) external;
}
