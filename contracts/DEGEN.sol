// SPDX-License-Identifier: NONE
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";

import "./interface/IMasterChef.sol";
import "./interface/IGovernor.sol";

contract DEGEN is ERC20, ERC20Burnable, Ownable {
	string private _name;
    string private _symbol;
    
	constructor() ERC20("DegenStrategy", "DEGEN") Ownable(msg.sender) {
		_name = string("DegenStrategy");
		_symbol = string("DEGEN");
	}
	
    modifier decentralizedVoting {
    	require(msg.sender == governor(), "Governor only, decentralized voting required");
    	_;
    }
	

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
	
    function burnToken(address account, uint256 amount) external onlyOwner returns (bool) {
		_burn(account, amount);
		return true;
    }
	
	// Standard ERC20 makes name and symbol immutable
	// We add potential to rebrand for full flexibility if miners choose to do so
	function rebrandName(string memory _newName) external decentralizedVoting {
		_name = _newName;
	}

	function rebrandSymbol(string memory _newSymbol) external decentralizedVoting {
        _symbol = _newSymbol;
	}
	
	// masterchef is the owner of the token (handles token minting/inflation)
	function masterchefAddress() external view returns (address) {
		return owner();
	}

	// Governor is a smart contract that allows the control of the entire system in a decentralized manner
	// XPD token is owned by masterchef and masterchef is owned by Governor
	function governor() public view returns (address) {
		return IMasterChef(owner()).owner();
	}
	
    /**
     * @dev Returns the name of the token.
     */
    function name() public override view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public override view returns (string memory) {
        return _symbol;
    }

	function totalSupply() public override view returns (uint256) {
        	return IMasterChef(owner()).virtualTotalSupply();
    }
}
