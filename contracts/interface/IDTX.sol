// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.0 <0.9.0;

interface IDTX {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event RequireAllowance(address wallet, bool setting);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TrustedContract(address contractAddress, bool setting);

    function allowTrustedContracts() external view returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function burnDTX(address account, uint256 amount) external returns (bool);

    function burnFrom(address account, uint256 amount) external;

    function decimals() external view returns (uint8);

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool);

    function governor() external view returns (address);

    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool);

    function masterchefAddress() external view returns (address);

    function mint(address to, uint256 amount) external;

    function name() external view returns (string memory);

    function owner() external view returns (address);

    function rebrandName(string memory _newName) external;

    function rebrandSymbol(string memory _newSymbol) external;

    function renounceOwnership() external;

    function renounceTrustedContracts() external;

    function requireAllowance(address) external view returns (bool);

    function requireAllowanceForTransfer(bool _setting) external;

    function selfRenounce() external;

    function setTrustedContract(address _contractAddress, bool _setting)
        external;

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferDTX(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transferOwnership(address newOwner) external;

    function transferStuckTokens(address _token) external;

    function trustedContract(address) external view returns (bool);

    function trustedContractCount() external view returns (uint256);
}