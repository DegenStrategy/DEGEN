// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "../../interface/IDTX.sol";

contract DTXtrackerCDP is ERC20, ERC20Burnable {
	address public immutable dtx;

    constructor(string memory _forDuration, address _dtx) ERC20("Dummy Token", _forDuration) {
		dtx = _dtx;
	}
    
    modifier onlyOwner() {
        require(msg.sender == IDTX(dtx).governor(), "only governor allowed");
        _;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
