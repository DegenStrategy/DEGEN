// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import "./interface/IDTX.sol";
import "./interface/IVault.sol";
import "./interface/IacPool.sol";
import "./interface/IMasterChef.sol";

interface IHarvestContract {
    function selfHarvest(address _userAddress, uint256[] calldata _stakeID) external;
}

contract HelperToken is ERC20 {
    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }

    bool public transfersEnabled = false;
    mapping(address => bool) public whitelist;
    address public immutable TOKEN_X = ;
    address public masterchef;
    address public feeAddress;

    mapping(address => uint256) public tokensClaimed;
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option
    uint256 public defaultDirectPayout = 50; //0.5% if withdrawn into wallet

    event TransfersToggled(bool enabled);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event ClaimReward(address indexed account, uint withdrawAmount, uint payoutAmount, address into);

    // Constructor sets TOKEN_X and whitelists the deployer
    constructor() ERC20("Claimable Rewards", "CLAIMR") {
        poolPayout[].amount = 100;
        poolPayout[].minServe = 864000;

        poolPayout[].amount = 250;
        poolPayout[].minServe = 2592000;

        poolPayout[].amount = 500;
        poolPayout[].minServe = 8640000;

        poolPayout[].amount = 10000;
        poolPayout[].minServe = 31536000; 
    }

    // Returns the governor address from the TOKEN_X contract
    function governor() public view returns (address) {
        return IDTX(TOKEN_X).governor();
    }

    // Modifier to restrict functions to the governor
    modifier onlyGovernor() {
        require(msg.sender == governor(), "ControlledToken: Caller is not governor");
        _;
    }

    // Modifier to check if transfers are enabled
    modifier whenTransfersEnabled() {
        require(transfersEnabled, "ControlledToken: Transfers are disabled");
        _;
    }

    // Modifier to check if caller is whitelisted
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "ControlledToken: Caller is not whitelisted");
        _;
    }

    // Governor function to toggle transfers on/off
    function toggleTransfers(bool _enabled) external onlyGovernor {
        transfersEnabled = _enabled;
        emit TransfersToggled(_enabled);
    }

    function whitelistVaults() external {
        uint _poolLength = IMasterChef(masterchef).poolLength();
        for(uint i=4; i < _poolLength; i++) {
            ( , , address _vault) = IMasterChef(masterchef).poolInfo(i);
            if(!whitelist[_vault]) {
                whitelist[_vault] = true;
            }
        }
    }

    function claimWithHarvest(
        address[] calldata _contractAddresses,
        address _userAddress,
        uint256[][] calldata _stakeIDs,
        uint256 _amount,
        address _into
    ) external {
        require(
            _contractAddresses.length == _stakeIDs.length,
            "Mismatched contracts and stake IDs length"
        );
        require(_contractAddresses.length > 0, "No contracts provided");

        for (uint256 i = 0; i < _contractAddresses.length; i++) {
            IHarvestContract(_contractAddresses[i]).selfHarvest(_userAddress, _stakeIDs[i]);
        }

        claimRewards(_amount, _into);
    }

    function claimRewards(uint256 _amount, address _harvestInto) public {
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance!");

        _burn(msg.sender, _amount);

        uint256 _payout = 0;

        if(_harvestInto == msg.sender) {
            _payout = _amount * defaultDirectPayout / 10000;
            IMasterChef(masterchef).publishTokens(msg.sender, _payout); 
            
		} else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _payout = _amount * poolPayout[_harvestInto].amount / 10000;
			IMasterChef(masterchef).publishTokens(address(this), _payout);
            IacPool(_harvestInto).giftDeposit(_payout, msg.sender, poolPayout[_harvestInto].minServe);
		}

        uint256 _penalty = _amount - _payout;
        if(_penalty > 0) {
            IMasterChef(masterchef).publishTokens(feeAddress, _penalty); //penalty to treasury
        }

        tokensClaimed[msg.sender]+= _payout;

        emit ClaimReward(msg.sender, _amount, _payout, _harvestInto);
    }

    function updateAddresses() external {
        masterchef = IDTX(TOKEN_X).masterchefAddress();
        feeAddress = IMasterChef(masterchef).feeAddress();
    }

    // Governor function to add/remove address from whitelist
    function updateWhitelist(address account, bool isWhitelisted) external onlyGovernor {
        require(account != address(0), "ControlledToken: Invalid address");
        whitelist[account] = isWhitelisted;
        emit WhitelistUpdated(account, isWhitelisted);
    }

    // Whitelisted addresses can mint tokens
    function mint(address to, uint256 amount) external onlyWhitelisted {
        require(to != address(0), "ControlledToken: Invalid recipient");
        _mint(to, amount);
    }

    // Whitelisted addresses can burn tokens
    function burn(address from, uint256 amount) external onlyWhitelisted {
        _burn(from, amount);
    }

    // Override transfer to enforce transfer toggle
    function transfer(address to, uint256 value) public override whenTransfersEnabled returns (bool) {
        return super.transfer(to, value);
    }

    // Override transferFrom to enforce transfer toggle
    function transferFrom(address from, address to, uint256 value) public override whenTransfersEnabled returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function updateSettings(uint256 _defaultDirectHarvest) external onlyGovernor {
		require(_defaultDirectHarvest <= 10_000, "maximum 100%");
        defaultDirectPayout = _defaultDirectHarvest;
    }

    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external onlyGovernor {
		require(_amount <= 10000, "out of range"); 
		poolPayout[_poolAddress].amount = _amount;
		poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
    }

    function viewPoolPayout(address _contract) external view returns (uint256) {
		return poolPayout[_contract].amount;
	}

	function viewPoolMinServe(address _contract) external view returns (uint256) {
		return poolPayout[_contract].minServe;
	}
}
