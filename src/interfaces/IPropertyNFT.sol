// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPropertyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getTokensByOwner(address owner) external view returns (uint256[] memory);
}
