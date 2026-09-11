// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDisputeResolver {
    function escalate(address agreement) external;
    function resolve(address agreement, bool tenantWins) external;
}
