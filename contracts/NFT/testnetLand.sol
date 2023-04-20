// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract DecentralizeXland is ERC721 {
    uint256 public tokenCount;

    constructor() ERC721("DecentralizeX Virtual Land", "DTX LAND") {}

    function createNew(address player) public {
        _mint(player, tokenCount);
        tokenCount++;
    }
}
