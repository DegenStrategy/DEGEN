// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "../interface/IDTX.sol";

contract PulseDAOLand is ERC721URIStorage {
	string private _name;
    string private _symbol;

    uint256 public tokenCount;
	address public tokenAddress;
	bool public allowMint = true;
	
	event SetTokenURI(uint256 tokenID, string URI);

    constructor(address _dtx, string memory _nameC, string memory _tickerC) ERC721("PulseDAO Virtual Land", "XPD LAND") {
		tokenAddress = _dtx;
		_name = _nameC;
		_symbol = _tickerC;
	}
	
	
	modifier decentralizedVoting {
    	require(msg.sender == IDTX(tokenAddress).governor(), "Governor only, decentralized voting required");
    	_;
    }
	
	
    function mintLand(address mintTo) external {
		require(allowMint, "minting has been renounced");
        require(msg.sender == IDTX(tokenAddress).governor(), "governor only");
		_mint(mintTo, tokenCount);
		tokenCount++;
    }
	
	// users can set land outlook
	function setTokenURI(uint256 _tokenId, string memory _tokenURI) external {
		require(msg.sender == ownerOf(_tokenId), "you are not the token owner!");
		_setTokenURI(_tokenId, _tokenURI);
		emit SetTokenURI(_tokenId, _tokenURI);
	}
	
	function renounceMint() external {
		require(msg.sender == IDTX(tokenAddress).governor(), "governor only");
		allowMint = false;
	}
	
	//Standard ERC20 makes name and symbol immutable
	//We add potential to rebrand for full flexibility if stakers choose to do so through voting
	function rebrandName(string memory _newName) external decentralizedVoting {
		_name = _newName;
	}
	function rebrandSymbol(string memory _newSymbol) external decentralizedVoting {
        _symbol = _newSymbol;
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
}
