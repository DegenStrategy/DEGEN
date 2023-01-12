// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface INFTstaking {
    event AddVotingCredit(address indexed user, uint256 amount);
    event Deposit(
        address indexed tokenAddress,
        uint256 indexed tokenID,
        address indexed depositor,
        uint256 shares,
        uint256 nftAllocation,
        address allocContract
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 _stakeID,
        address indexed token,
        uint256 tokenID
    );
    event Harvest(
        address indexed harvester,
        address indexed benficiary,
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
        address indexed token,
        uint256 indexed tokenID,
        uint256 shares,
        uint256 harvestAmount
    );

    function MINIMUM_ALLOCATION() external view returns (uint256);

    function admin() external view returns (address);

    function allocationContract() external view returns (address);

    function calculateTotalPendingDTXRewards() external view returns (uint256);

    function cashoutAllToCredit() external;

    function defaultDirectPayout() external view returns (uint256);

    function defaultFeeToPay() external view returns (uint256);

    function defaultHarvest() external view returns (address);

    function defaultHarvestThreshold() external view returns (uint256);

    function deposit(
        address _tokenAddress,
        uint256 _tokenID,
        address _allocationContract
    ) external;

    function dummyToken() external view returns (address);

    function emergencyWithdraw(uint256 _stakeID) external;

    function emergencyWithdrawAll() external;

    function getNrOfStakes(address _user) external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    function getUserShares(address _wallet, uint256 _stakeID)
        external
        view
        returns (uint256);

    function getUserTotals(address _user)
        external
        view
        returns (uint256, uint256);

    function harvest() external;

    function massHarvest(
        address[] memory beneficiary,
        uint256[][] memory stakeID
    ) external;

    function masterchef() external view returns (address);

    function maxHarvestPublic(address _staker, uint256 _stakeID)
        external
        view
        returns (uint256);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external returns (bytes4);

    function poolID() external view returns (uint256);

    function poolPayout(address)
        external
        view
        returns (uint256 amount, uint256 minServe);

    function proxyHarvest(address _beneficiary) external;

    function proxyHarvestCustom(address _beneficiary, uint256[] memory _stakeID)
        external;

    function publicBalanceOf() external view returns (uint256);

    function rebalanceNFT(
        address _staker,
        uint256 _stakeID,
        bool isAllocationContractReplaced,
        address _allocationContract
    ) external;

    function selfHarvest(address _harvestInto) external;

    function selfHarvestCustom(uint256[] memory _stakeID, address _harvestInto)
        external;

    function setAdmin() external;

    function setMasterChefAddress(address _masterchef, uint256 _newPoolID)
        external;

    function setPoolPayout(
        address _poolAddress,
        uint256 _amount,
        uint256 _minServe
    ) external;

    function setUserSettings(
        uint256 _harvestThreshold,
        uint256 _feeToPay,
        address _harvestInto
    ) external;

    function startEarning() external;

    function stopEarning(uint256 _withdrawAmount) external;

    function syncCreditContract() external;

    function token() external view returns (address);

    function tokenDebt() external view returns (uint256);

    function totalShares() external view returns (uint256);

    function treasury() external view returns (address);

    function updateAllocationContract() external;

    function updateSettings(
        address _defaultHarvest,
        uint256 _threshold,
        uint256 _defaultFee,
        uint256 _defaultDirectHarvest
    ) external;

    function userInfo(address, uint256)
        external
        view
        returns (
            address tokenAddress,
            uint256 tokenID,
            uint256 shares,
            uint256 debt,
            address allocContract
        );

    function userSettings(address)
        external
        view
        returns (
            address pool,
            uint256 harvestThreshold,
            uint256 feeToPay
        );

    function viewStakeEarnings(address _user, uint256 _stakeID)
        external
        view
        returns (uint256);

    function viewUserTotalEarnings(address _user)
        external
        view
        returns (uint256);

    function votingCredit(uint256 _shares, uint256 _stakeID) external;

    function votingCreditAddress() external view returns (address);

    function withdraw(uint256 _stakeID, address _harvestInto) external;

    function withdrawDummy(uint256 _amount) external;

    function withdrawStuckTokens(address _tokenAddress) external;
}
