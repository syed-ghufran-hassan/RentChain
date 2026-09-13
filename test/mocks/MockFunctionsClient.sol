// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/RentalOracle.sol";

contract MockFunctionsClient is IFunctionsClient {
    bytes32 public nextRequestId = keccak256("mock-req-1");

    function sendRequest(
        string memory,
        bytes[] memory,
        uint64,
        uint32,
        bytes32
    ) external override returns (bytes32) {
        return nextRequestId;
    }

    function setNextRequestId(bytes32 id) external {
        nextRequestId = id;
    }
}