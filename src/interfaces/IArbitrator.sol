// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbitrator {
    /// @notice Create a dispute with the given number of choices.
    /// @param choices Number of possible rulings (e.g., 2 for tenant/owner).
    /// @param evidence URI to off-chain evidence (IPFS hash).
    function createDispute(uint256 choices, string calldata evidence) external payable returns (uint256 disputeId);

    /// @notice Cost (in wei) to create a dispute.
    function arbitrationCost() external view returns (uint256);
}
