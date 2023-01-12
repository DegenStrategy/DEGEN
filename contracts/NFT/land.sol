// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "../interface/IDTX.sol";

contract DecentralizeXland is ERC721URIStorage {
    uint256 public tokenCount;
	address public tokenAddress;
	bool public allowMint = true;
	
	event SetTokenURI(uint256 tokenID, string URI);

    constructor(address _dtx) ERC721("DecentralizeX Virtual Land", "DTX LAND") {
		tokenAddress = _dtx;
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
}