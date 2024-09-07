// test/RentalManagement.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentalManagement.sol";

contract RentalManagementTest is Test {
    RentalManagement rentalManagement;
    address owner = address(0x123);
    address tenant = address(0x456);

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
}
