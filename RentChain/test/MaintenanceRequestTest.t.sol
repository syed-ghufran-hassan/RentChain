// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MaintenanceRequest.sol";

contract MaintenanceRequestTest is Test {
    MaintenanceRequest maintenanceRequest;

    // Set up the contract before each test
    function setUp() public {
        maintenanceRequest = new MaintenanceRequest();
    }
function testCreateRequest() public {
    uint256 propertyId = 1;
    string memory description = "Leaky faucet";

    // Create a maintenance request
    maintenanceRequest.createRequest(propertyId, description);

    // Retrieve the request details
    MaintenanceRequest.Request memory request = maintenanceRequest.getRequest(0); // Assuming this is the first request

    // Assertions
    assertEq(request.tenant, address(this), "Tenant address should match");
    assertEq(request.propertyId, propertyId, "Property ID should match");
    assertEq(request.description, description, "Description should match");
    assertEq(uint256(request.status), uint256(MaintenanceRequest.RequestStatus.Pending), "Status should be Pending");
    require(request.createdAt > 0, "Creation timestamp should be set"); // Check the createdAt field
}
    function testResolveRequest() public {
        uint256 propertyId = 1;
        string memory description = "Leaky faucet";

        // Create the maintenance request
        maintenanceRequest.createRequest(propertyId, description);

        // Resolve the request
        maintenanceRequest.resolveRequest(0, MaintenanceRequest.RequestStatus.Resolved);

        // Retrieve the resolved request
        MaintenanceRequest.Request memory request = maintenanceRequest.getRequest(0);

        // Assert the status of the request
        assertEq(uint8(request.status), uint8(MaintenanceRequest.RequestStatus.Resolved), "Status should be Resolved");
    }

    function testFailResolveNonPendingRequest() public {
        uint256 propertyId = 1;
        string memory description = "Leaky faucet";

        // Create the maintenance request
        maintenanceRequest.createRequest(propertyId, description);

        // Resolve the request
        maintenanceRequest.resolveRequest(0, MaintenanceRequest.RequestStatus.Resolved);

        // Try to resolve it again, should fail
        vm.expectRevert("Request is already resolved");
        maintenanceRequest.resolveRequest(0, MaintenanceRequest.RequestStatus.Resolved);
    }

    function testGetTotalRequests() public {
        uint256 propertyId1 = 1;
        string memory description1 = "Leaky faucet";
        uint256 propertyId2 = 2;
        string memory description2 = "Broken window";

        // Create two maintenance requests
        maintenanceRequest.createRequest(propertyId1, description1);
        maintenanceRequest.createRequest(propertyId2, description2);

        // Assert the total number of requests
        assertEq(maintenanceRequest.getTotalRequests(), 2, "Total requests should be 2");
    }
}
