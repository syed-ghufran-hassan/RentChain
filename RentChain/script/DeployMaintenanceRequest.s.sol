// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { MaintenanceRequest } from "../src/MaintenanceRequest.sol";

contract DeployMaintenanceRequest is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the MaintenanceRequest contract
        MaintenanceRequest maintenanceRequest = new MaintenanceRequest();

        // Log the address of the deployed contract
        emit ContractDeployed(address(maintenanceRequest));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

    // Define an event for logging the deployed contract address
    event ContractDeployed(address deployedAddress);
}
