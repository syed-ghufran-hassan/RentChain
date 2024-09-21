// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/DisputeResolution.sol";

contract DisputeResolutionTest is Test {
    DisputeResolution disputeResolution;

    address arbitrator;
    address tenant;
    address owner;
    uint256 propertyId = 1;
    string reason = "Deposit not returned";
    uint256 amount = 100 ether;

    function setUp() public {
        arbitrator = address(this); // Using the test contract as the arbitrator
        tenant = address(0x1);
        owner = address(0x2);
        disputeResolution = new DisputeResolution(arbitrator);
    }

    function testCreateDispute() public {
        vm.startPrank(tenant);
        disputeResolution.createDispute(owner, propertyId, reason, amount);
        
        // Check if the dispute was created correctly
        DisputeResolution.Dispute memory dispute = disputeResolution.getDispute(0);
        
        assertEq(dispute.tenant, tenant);
        assertEq(dispute.owner, owner);
        assertEq(dispute.reason, reason);
        assertEq(uint(dispute.status), uint(DisputeResolution.DisputeStatus.Pending));
        assertEq(dispute.propertyId, propertyId);
        assertEq(dispute.amount, amount);
        vm.stopPrank();
    }

    function testResolveDispute() public {
        vm.startPrank(tenant);
        disputeResolution.createDispute(owner, propertyId, reason, amount);
        vm.stopPrank();

        // Resolve the dispute
        vm.startPrank(arbitrator);
        disputeResolution.resolveDispute(0, DisputeResolution.DisputeStatus.Resolved);
        vm.stopPrank();

        // Check if the dispute status is updated
        DisputeResolution.Dispute memory dispute = disputeResolution.getDispute(0);
        assertEq(uint(dispute.status), uint(DisputeResolution.DisputeStatus.Resolved));
    }

    function testFailResolveDisputeWithoutArbitrator() public {
        vm.startPrank(tenant);
        disputeResolution.createDispute(owner, propertyId, reason, amount);
        vm.stopPrank();

        // Attempting to resolve the dispute as tenant should fail
        vm.startPrank(tenant);
        vm.expectRevert();
        disputeResolution.resolveDispute(0, DisputeResolution.DisputeStatus.Resolved);
        vm.stopPrank();
    }

    function testGetTotalDisputes() public {
        assertEq(disputeResolution.getTotalDisputes(), 0);
        
        vm.startPrank(tenant);
        disputeResolution.createDispute(owner, propertyId, reason, amount);
        vm.stopPrank();

        assertEq(disputeResolution.getTotalDisputes(), 1);
    }
}
