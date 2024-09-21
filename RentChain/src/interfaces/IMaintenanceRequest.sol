// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMaintenanceRequest {
    function createRequest(address tenant, string calldata description) external returns (uint256);
    function getRequest(uint256 requestId) external view returns (address, string memory, bool);
}
