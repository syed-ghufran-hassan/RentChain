// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyNFT is ERC721URIStorage, Ownable {
    uint256 private _nextTokenId = 1;

    mapping(address => uint256[]) private _ownerTokens;
    mapping(uint256 => uint256) private _tokenIndex;

    event PropertyRegistered(address indexed owner, uint256 indexed tokenId, string metadataURI);

    constructor() ERC721("RentChain Property", "RCP") Ownable(msg.sender) {}

    function registerProperty(string memory metadataURI) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        emit PropertyRegistered(msg.sender, tokenId, metadataURI);
        return tokenId;
    }

    // Override _update (v5) to maintain owner token lists
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId); // get current owner before transfer
        address result = super._update(to, tokenId, auth);

        // Handle owner list updates
        if (from != address(0) && to != address(0) && from != to) {
            // Transfer
            _removeTokenFromOwner(from, tokenId);
            _addTokenToOwner(to, tokenId);
        } else if (from == address(0) && to != address(0)) {
            // Mint – only add, no removal
            _addTokenToOwner(to, tokenId);
        } else if (from != address(0) && to == address(0)) {
            // Burn – only remove, no addition
            _removeTokenFromOwner(from, tokenId);
        }

        return result;
    }

    function _addTokenToOwner(address owner, uint256 tokenId) internal {
        _ownerTokens[owner].push(tokenId);
        _tokenIndex[tokenId] = _ownerTokens[owner].length - 1;
    }

    function _removeTokenFromOwner(address owner, uint256 tokenId) internal {
        uint256 index = _tokenIndex[tokenId];
        uint256 lastIndex = _ownerTokens[owner].length - 1;
        if (index != lastIndex) {
            uint256 lastTokenId = _ownerTokens[owner][lastIndex];
            _ownerTokens[owner][index] = lastTokenId;
            _tokenIndex[lastTokenId] = index;
        }
        _ownerTokens[owner].pop();
        delete _tokenIndex[tokenId];
    }

    function getTokensByOwner(address owner) external view returns (uint256[] memory) {
        return _ownerTokens[owner];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}