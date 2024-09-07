// script/DeployRentalManagement.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {RentalManagement} from "../src/RentalManagement.sol";

contract DeployRentalManagement is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the contract
        RentalManagement rentalManagement = new RentalManagement();

        // Log the address of the deployed contract
        // Direct logging is not supported here; use foundry's built-in tools or manually verify
        emit ContractDeployed(address(rentalManagement));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

    // Define an event for logging
    event ContractDeployed(address deployedAddress);
}
