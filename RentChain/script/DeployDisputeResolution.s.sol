// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { DisputeResolution } from "../src/DisputeResolution.sol";

contract DeployDisputeResolution is Script {
    address private arbitratorAddress; // Replace with the actual arbitrator address

    function setArbitratorAddress(address _arbitrator) internal {
        arbitratorAddress = _arbitrator;
    }

    function run() external {
        // Set the arbitrator's address (update with the correct address)
        setArbitratorAddress(0x1CDeaea756c78af1b691E04702D968aC7e72E22F);

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the contract with the arbitrator's address
        DisputeResolution disputeResolution = new DisputeResolution(arbitratorAddress);

        // Log the address of the deployed contract
        emit ContractDeployed(address(disputeResolution));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

    // Define an event for logging
    event ContractDeployed(address deployedAddress);
}
