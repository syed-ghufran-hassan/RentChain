// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDisputeResolution {
    function createDispute(address owner, uint256 propertyId, string calldata reason, uint256 amount) external returns (uint256);
    function getDispute(uint256 disputeId) external view returns (address, address, string memory, uint8, uint256, uint256);
}
