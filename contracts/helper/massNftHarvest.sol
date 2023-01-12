// SPDX-License-Identifier: NONE

pragma solidity 0.8.0;

interface INFTStaking {
	function proxyHarvestCustom(address _beneficiary, uint256[] calldata _stakeID) external;
}

contract NftHarvestHelper {
    address public nftStakingContract;

    constructor(address _c) {
        nftStakingContract = _c;
    }

    function massHarvest(address[] calldata beneficiary, uint256[][] calldata stakeID) external {
        for(uint256 i=0; i<beneficiary.length; i++) {
            INFTStaking(nftStakingContract).proxyHarvestCustom(beneficiary[i], stakeID[i]);
        }
    }
}