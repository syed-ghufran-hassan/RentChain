// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/interfaces/IArbitrator.sol";

interface IKlerosResolverRule {
    function rule(uint256 disputeId, uint256 ruling) external;
}

contract MockArbitrator is IArbitrator {
    uint256 public nextDisputeId = 1;
    uint256 public cost = 0.01 ether;

    mapping(uint256 => string) public evidenceOf;
    mapping(uint256 => uint256) public choicesOf;

    event DisputeCreated(uint256 indexed disputeId, uint256 choices, string evidence);

    function createDispute(uint256 choices, string calldata evidence)
        external
        payable
        override
        returns (uint256 disputeId)
    {
        require(msg.value >= cost, "Insufficient fee");
        disputeId = nextDisputeId++;
        evidenceOf[disputeId] = evidence;
        choicesOf[disputeId] = choices;
        emit DisputeCreated(disputeId, choices, evidence);
    }

    function arbitrationCost() external view override returns (uint256) {
        return cost;
    }

    function setCost(uint256 _cost) external {
        cost = _cost;
    }

    /// @notice Helper to trigger a ruling from inside the arbitrator.
    ///         This makes `msg.sender == address(this)` for the resolver call.
    function triggerRule(address resolver, uint256 disputeId, uint256 ruling) external {
        IKlerosResolverRule(resolver).rule(disputeId, ruling);
    }
}
