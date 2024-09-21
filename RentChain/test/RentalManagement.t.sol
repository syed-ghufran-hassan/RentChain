// test/RentalManagement.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentalManagement.sol";

contract RentalManagementTest is Test {
    RentalManagement rentalManagement;
    address owner = address(0x123);
    address tenant = address(0x456);


    struct Property {
        address owner;
        string name;
        string location;
        uint256 rentPerMonth;
        bool isRented;
    }


    function setUp() public {
        rentalManagement = new RentalManagement();
        vm.prank(owner);
        rentalManagement.registerProperty("Test Property", "123 Test St", 1 ether);
    }

    function testRegisterProperty() public {
        (address _owner, string memory name, string memory location, uint256 rentPerMonth, bool isRented) = rentalManagement.properties(0);
        
        assertEq(_owner, owner);
        assertEq(name, "Test Property");
        assertEq(location, "123 Test St");
        assertEq(rentPerMonth, 1 ether);
        assertFalse(isRented);
    }

    function testRentProperty() public {
        vm.deal(tenant, 2 ether); // Send 2 ether to tenant
        vm.startPrank(tenant);
        rentalManagement.rentProperty{value: 2 ether}(0, block.timestamp, block.timestamp + 30 days);
        vm.stopPrank();

        (address _tenant, uint256 propertyId, uint256 deposit, uint256 rentalStart, uint256 rentalEnd) = rentalManagement.rentalAgreements(0);

        assertEq(_tenant, tenant);
        assertEq(propertyId, 0);
        assertEq(deposit, 1 ether);
        assertTrue(rentalStart > 0);
        assertTrue(rentalEnd > rentalStart);
    }

    function testReturnDeposit() public {
       // Allocate Ether to tenant and set up rental
    vm.deal(tenant, 2 ether);
    vm.startPrank(tenant);
    uint256 rentalStart = block.timestamp;
    uint256 rentalEnd = block.timestamp + 1 days; // Short rental period for testing
    rentalManagement.rentProperty{value: 2 ether}(0, rentalStart, rentalEnd);
    vm.stopPrank();

    // Fast-forward time to ensure rental period has ended
    vm.warp(rentalEnd + 10); // Move forward in time past the rental end

    // Return the deposit
    vm.prank(owner);
    rentalManagement.returnDeposit(0);

    // Check deposit refund
    assertEq(address(tenant).balance, 1 ether); // Deposit should be refunded
    }

    function testFailRentPropertyInsufficientFunds() public {
        vm.startPrank(tenant);
        rentalManagement.rentProperty{value: 0.5 ether}(0, block.timestamp, block.timestamp + 30 days); // Not enough funds
        vm.stopPrank();
    }


    function testRentPropertyWithInsufficientFunds() public {
        // Attempt to rent a property with insufficient Ether to cover both rent and deposit.
    // Setup initial state
    vm.startPrank(tenant);
    uint256 rentalStart = block.timestamp;
    uint256 rentalEnd = block.timestamp + 1 days; // Short rental period for testing

    // Try renting the property with less than the required amount
    vm.expectRevert(); // Expect revert message
    rentalManagement.rentProperty{value: 0.5 ether}(0, rentalStart, rentalEnd);

    vm.stopPrank();
}


    function testReturnDepositBeforeRentalPeriodEnds() public {
        // Attempt to return the deposit before the rental period has ended.
    // Allocate Ether to tenant and set up rental
    vm.deal(tenant, 2 ether);
    vm.startPrank(tenant);
    uint256 rentalStart = block.timestamp;
    uint256 rentalEnd = block.timestamp + 1 days; // Short rental period for testing
    rentalManagement.rentProperty{value: 2 ether}(0, rentalStart, rentalEnd);
    vm.stopPrank();

    // Attempt to return the deposit before rental period ends
    vm.startPrank(owner);
    vm.expectRevert("Rental period not ended");
    rentalManagement.returnDeposit(0);
    vm.stopPrank();
}


    function testNonOwnerCallingReturnDeposit() public {
      // Step 1: Register a property by the actual owner (not this test's msg.sender)
    rentalManagement.registerProperty("Test Property", "123 Test St", 1 ether);

    // Step 2: Rent the property (to complete the flow and enable returning the deposit later)
    rentalManagement.rentProperty{value: 1 ether}(0, block.timestamp, block.timestamp + 30 days);

    // Step 3: Attempt to call returnDeposit() by a non-owner
    address nonOwner = address(0xBEEF);
    vm.prank(nonOwner); // This sets the msg.sender to the nonOwner address

    // Expect the call to revert because the nonOwner is not allowed to return the deposit
    vm.expectRevert();
    rentalManagement.returnDeposit(0);


}


    function testRentPropertyWithZeroDeposit() public {
        //Attempt to rent a property without sending the required deposit amount (edge case where deposit is zero).
    // Setup initial state
    vm.startPrank(tenant);
    uint256 rentalStart = block.timestamp;
    uint256 rentalEnd = block.timestamp + 1 days; // Short rental period for testing

    // Try renting the property with zero deposit
    vm.expectRevert();
    rentalManagement.rentProperty{value: 1 ether}(0, rentalStart, rentalEnd); // Rent is 1 ether, deposit should be equal to rent
    vm.stopPrank();
}


    function testViewPropertiesWithNoRegisteredProperties() public {

   // Create a new instance of RentalManagement with no properties registered
    rentalManagement = new RentalManagement();

    // Retrieve the list of properties
    RentalManagement.Property[] memory propertiesList = rentalManagement.viewProperties();

    // Ensure the properties array is empty
    assertEq(propertiesList.length, 0, "Properties should be empty when none are registered");
}

function testReturnDepositWithNoDeposit() public {
        // Register a property but don't rent it
        rentalManagement.registerProperty("Luxury Apartment", "New York", 1 ether);

        // Expect the function to revert due to no deposit being available
        vm.expectRevert();
        rentalManagement.returnDeposit(0);
    }


    function testRentPropertyWithMaximumValue() public {

        // Attempt to rent a property with the maximum value allowed in a transaction
    // Setup initial state
    vm.startPrank(tenant);
    uint256 rentalStart = block.timestamp;
    uint256 rentalEnd = block.timestamp + 1 days; // Short rental period for testing

    // Use a very large value (for testing purposes, ensure this is realistic for your use case)
    uint256 maxValue = type(uint256).max;
    vm.expectRevert(); // Adjust according to your contract's response to large values
    rentalManagement.rentProperty{value: maxValue}(0, rentalStart, rentalEnd);
    vm.stopPrank();
}

    function testFailRegisterPropertyTwice() public {
        string memory name1 = "Luxury Apartment";
        string memory location1 = "New York";
        uint256 rentPerMonth1 = 1 ether;

        string memory name2 = "Another Apartment";
        string memory location2 = "Los Angeles";
        uint256 rentPerMonth2 = 2 ether;

        // Register the first property
        rentalManagement.registerProperty(name1, location1, rentPerMonth1);

        // Try to register another property, which should fail
        rentalManagement.registerProperty(name2, location2, rentPerMonth2);
    }

    function testAnotherOwnerCanRegisterProperty() public {
    // Register the first property with this address
    rentalManagement.registerProperty("Luxury Apartment", "New York", 1 ether);

    // Simulate another address using vm.prank
    address newOwner = address(0xBEEF);
    vm.prank(newOwner); // Change msg.sender to newOwner

    // This should revert if the contract logic is correct
    rentalManagement.registerProperty("Beach House", "Miami", 2 ether);

    // Ensure the function reverts if the msg.sender is the same as the first owner
    vm.expectRevert("You are already a property owner");

    // Trying to register again with the same msg.sender should fail
    rentalManagement.registerProperty("Luxury Apartment", "New York", 1 ether);
}


    function testRentPropertyWithSufficientFunds() public {
        // Register a property
        rentalManagement.registerProperty("Luxury Apartment", "New York", 1 ether);
        
        // Set the start and end dates for the rental
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 30 days;

        // Rent the property with sufficient funds
        vm.deal(address(this), 2 ether); // Allocate 2 ether to this address
        rentalManagement.rentProperty{value: 1 ether}(0, start, end);
        
        // Check if the deposit is stored correctly
        assertEq(rentalManagement.deposits(0), 1 ether, "Deposit should be 1 ether");
        
        // Verify that the property is marked as rented
        (, , , , bool isRented) = rentalManagement.properties(0);
        assertTrue(isRented, "Property should be marked as rented");
    }


   
        function testRentalHistory() public {
       uint256 start = block.timestamp;
    uint256 end = block.timestamp + 30 days;

    // Rent the property
    vm.prank(tenant);
    rentalManagement.rentProperty{value: 1 ether}(0, block.timestamp, block.timestamp + 30 days);

    // Retrieve rental history for the tenant
    RentalManagement.RentalHistory memory tenantRental = rentalManagement.GettenantHistory(tenant, 0);
    assertEq(tenantRental.tenant, tenant, "Tenant address mismatch");
    assertEq(tenantRental.propertyId, 0, "Property ID mismatch");
    assertEq(tenantRental.rentalStart, block.timestamp, "Rental start timestamp mismatch");
    assertEq(tenantRental.rentalEnd, block.timestamp + 30 days, "Rental end timestamp mismatch");
    assertEq(tenantRental.deposit, 1 ether, "Deposit amount mismatch");

    // Retrieve rental history for the owner
    RentalManagement.RentalHistory memory ownerRental = rentalManagement.GetownerHistory(owner, 0);
    assertEq(ownerRental.tenant, tenant, "Tenant address mismatch");
    assertEq(ownerRental.propertyId, 0, "Property ID mismatch");
    assertEq(ownerRental.rentalStart, block.timestamp, "Rental start timestamp mismatch");
    assertEq(ownerRental.rentalEnd, block.timestamp + 30 days, "Rental end timestamp mismatch");
    assertEq(ownerRental.deposit, 1 ether, "Deposit amount mismatch");

    }
    }
    
