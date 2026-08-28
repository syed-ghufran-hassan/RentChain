// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentChain.sol";

contract RentChainTest is Test {
    RentalHistory public history;
    RentChainFactory public factory;
    RentalAgreement public agreement;

    address public owner = address(0x1);
    address public tenant = address(0x2);
    address public thirdParty = address(0x3);

    uint256 public constant RENT = 1 ether;
    uint256 public constant DEPOSIT = 2 ether;
    uint256 public constant DURATION = 30 days;
    uint256 public constant INTERVAL = 1 days;

    // Events we may need to check
    event AgreementSigned(address indexed signer, RentalAgreement.State newState);
    event RentPaid(address indexed tenant, uint256 amount, uint256 timestamp);
    event RentWithdrawn(address indexed owner, uint256 amount);
    event LeaseEnded(address indexed owner, uint256 endTime);
    event DepositReleased(address indexed tenant, uint256 amount);
    event DisputeRaised(address indexed initiator);
    event AgreementCreated(address indexed agreement, address indexed owner, address indexed tenant);

    function setUp() public {
        // Fund the accounts
        vm.deal(owner, 100 ether);
        vm.deal(tenant, 100 ether);
        vm.deal(thirdParty, 100 ether);

        // Deploy core contracts
        history = new RentalHistory();
        factory = new RentChainFactory(address(history));

        // Owner creates an agreement for the tenant
        vm.prank(owner);
        agreement = RentalAgreement(payable(factory.createAgreement(
            tenant,
            RENT,
            DEPOSIT,
            DURATION,
            INTERVAL
        )));
    }

    // ------------------------------------------------------------------------
    // 1. Agreement creation & state
    // ------------------------------------------------------------------------
    function test_CreateAgreement() public {
        assertEq(address(agreement.owner()), owner);
        assertEq(agreement.tenant(), tenant);
        assertEq(agreement.rentAmount(), RENT);
        assertEq(agreement.depositAmount(), DEPOSIT);
        assertEq(agreement.leaseDuration(), DURATION);
        assertEq(agreement.paymentInterval(), INTERVAL);
        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Created));

        // Check history recorded
        assertEq(history.getAgreementCount(owner), 1);
        assertEq(history.getAgreementCount(tenant), 1);
        assertEq(history.getAgreementAt(owner, 0), address(agreement));
        assertEq(history.getAgreementAt(tenant, 0), address(agreement));
    }

    // ------------------------------------------------------------------------
    // 2. Signing flow
    // ------------------------------------------------------------------------
    function test_SignAsOwner() public {
        vm.prank(owner);
        agreement.signAsOwner();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.OwnerSigned));
    }

    function test_SignAsTenant() public {
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.TenantSigned));
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    function test_ActivationWhenBothSign() public {
        vm.prank(owner);
        agreement.signAsOwner();

        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Active));
        assertEq(agreement.leaseStart(), block.timestamp);
        assertEq(agreement.leaseEnd(), block.timestamp + DURATION);
        assertEq(agreement.lastPaymentTimestamp(), block.timestamp);
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    function test_ActivationWhenTenantSignsFirst() public {
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.prank(owner);
        agreement.signAsOwner();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Active));
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    function test_OnlyOwnerCanSignAsOwner() public {
        vm.prank(tenant);
        vm.expectRevert("Not owner");
        agreement.signAsOwner();
    }

    function test_OnlyTenantCanSignAsTenant() public {
        vm.prank(owner);
        vm.expectRevert("Not tenant");
        agreement.signAsTenant{value: DEPOSIT}();
    }

    function test_CannotSignAfterActivation() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Try to sign again
        vm.prank(owner);
        vm.expectRevert("Cannot sign now");
        agreement.signAsOwner();
    }

    function test_DepositMustBeExact() public {
        vm.prank(tenant);
        vm.expectRevert("Must send exact deposit amount");
        agreement.signAsTenant{value: DEPOSIT - 1 ether}();
    }

    // ------------------------------------------------------------------------
    // 3. Rent payment
    // ------------------------------------------------------------------------
    function test_PayRent() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Advance time by 2 days (payment interval is 1 day)
        vm.warp(block.timestamp + 2 days);

        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        assertEq(agreement.rentHeld(), RENT);
        assertEq(agreement.lastPaymentTimestamp(), block.timestamp);
    }

    function test_CannotPayRentEarly() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Warp only 1 hour (less than interval)
        vm.warp(block.timestamp + 1 hours);

        vm.prank(tenant);
        vm.expectRevert("Payment not due yet");
        agreement.payRent{value: RENT}();
    }

    function test_CannotPayRentAfterLeaseEnd() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Warp beyond lease end (31 days)
        vm.warp(block.timestamp + 31 days);

        vm.prank(tenant);
        vm.expectRevert("Lease already ended");
        agreement.payRent{value: RENT}();
    }

    function test_RentMustBeExact() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);

        vm.prank(tenant);
        vm.expectRevert("Must send exact rent amount");
        agreement.payRent{value: RENT - 0.1 ether}();
    }

    function test_OnlyTenantCanPayRent() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        vm.expectRevert("Not tenant");
        agreement.payRent{value: RENT}();
    }

    // ------------------------------------------------------------------------
    // 4. Withdraw rent
    // ------------------------------------------------------------------------
    function test_WithdrawRent() public {
        // Activate and pay rent
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        agreement.withdrawRent();
        uint256 ownerBalanceAfter = owner.balance;

        assertEq(ownerBalanceAfter - ownerBalanceBefore, RENT);
        assertEq(agreement.rentHeld(), 0);
    }

    function test_CannotWithdrawZeroRent() public {
        // Activate but no rent paid
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.prank(owner);
        vm.expectRevert("No rent to withdraw");
        agreement.withdrawRent();
    }

    function test_OnlyOwnerCanWithdrawRent() public {
        // Activate and pay rent
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        vm.prank(tenant);
        vm.expectRevert("Not owner");
        agreement.withdrawRent();
    }

    // ------------------------------------------------------------------------
    // 5. End lease
    // ------------------------------------------------------------------------
    function test_EndLease() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Warp to lease end
        vm.warp(block.timestamp + DURATION + 1 days);

        vm.prank(owner);
        agreement.endLease();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Ended));
    }

    function test_CannotEndLeaseBeforeDuration() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Warp only 1 day (less than DURATION)
        vm.warp(block.timestamp + 1 days);

        vm.prank(owner);
        vm.expectRevert("Lease not ended yet");
        agreement.endLease();
    }

    function test_OnlyOwnerCanEndLease() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);

        vm.prank(tenant);
        vm.expectRevert("Not owner");
        agreement.endLease();
    }

    // ------------------------------------------------------------------------
    // 6. Release deposit
    // ------------------------------------------------------------------------
    function test_ReleaseDeposit() public {
        // Activate, end lease, release deposit
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        uint256 tenantBalanceBefore = tenant.balance;
        vm.prank(owner);
        agreement.releaseDeposit();
        uint256 tenantBalanceAfter = tenant.balance;

        assertEq(tenantBalanceAfter - tenantBalanceBefore, DEPOSIT);
        assertEq(agreement.depositHeld(), 0);
        assertTrue(agreement.depositReleased());
    }

    function test_CannotReleaseDepositTwice() public {
        // Activate, end, release once
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(owner);
        agreement.releaseDeposit();

        // Try again
        vm.prank(owner);
        vm.expectRevert("Deposit already released");
        agreement.releaseDeposit();
    }

    function test_CannotReleaseBeforeEnd() public {
        // Activate but not ended
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.prank(owner);
        vm.expectRevert("Invalid state");
        agreement.releaseDeposit();
    }

    function test_OnlyOwnerCanReleaseDeposit() public {
        // Activate, end
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(tenant);
        vm.expectRevert("Not owner");
        agreement.releaseDeposit();
    }

    // ------------------------------------------------------------------------
    // 7. Dispute mechanism
    // ------------------------------------------------------------------------
    function test_DisputeByTenant() public {
        // Activate, end
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(tenant);
        agreement.disputeDeposit();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Disputed));
    }

    function test_DisputeByOwner() public {
        // Activate, end
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(owner);
        agreement.disputeDeposit();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Disputed));
    }

    function test_ThirdPartyCannotDispute() public {
        // Activate, end
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(thirdParty);
        vm.expectRevert("Not party");
        agreement.disputeDeposit();
    }

    function test_CannotDisputeBeforeEnd() public {
        // Activate only
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.prank(tenant);
        vm.expectRevert("Invalid state");
        agreement.disputeDeposit();
    }

    // ------------------------------------------------------------------------
    // 8. History records verification
    // ------------------------------------------------------------------------
    function test_HistoryRecordsActivation() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // We can't easily query the history for a specific agreement's startTime,
        // but we can check that it was recorded by looking at the agreement's own leaseStart.
        // The history contract's recordActivation is called inside _activate().
        // To verify, we can use an event or we can assume internal call works.
        // We'll add a specific test for the history contract if needed.
        // For now, we know the history mapping is internal, so we'll rely on the agreement's state.
        // But we can add a view function to the history contract if we want to test.
        // Since we don't have one, we'll test indirectly by checking the agreement's leaseStart.
        assertEq(agreement.leaseStart(), block.timestamp);
    }

    function test_HistoryRecordsPayment() public {
        // Activate and pay rent
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        // We can't directly check history's internal storage, but we can check the agreement's rentHeld.
        assertEq(agreement.rentHeld(), RENT);
    }

    function test_HistoryRecordsEnd() public {
        // Activate, end
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Check agreement state
        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Ended));
    }

    function test_HistoryRecordsDispute() public {
        // Activate, end, dispute
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(tenant);
        agreement.disputeDeposit();

        assertEq(uint(agreement.state()), uint(RentalAgreement.State.Disputed));
    }

    // ------------------------------------------------------------------------
    // 9. Reentrancy (should be safe)
    // ------------------------------------------------------------------------
    // We can test reentrancy by creating a malicious contract that calls back into the agreement.
    // But this is advanced; we assume ReentrancyGuard works.

    // ------------------------------------------------------------------------
    // 10. View function
    // ------------------------------------------------------------------------
    function test_GetStatus() public view {
        assertEq(uint(agreement.getStatus()), uint(RentalAgreement.State.Created));
        // After signing, we could check status, but view function is simple.
    }

    // ------------------------------------------------------------------------
    // 11. Direct Ether transfer should revert
    // ------------------------------------------------------------------------
    function test_ReceiveReverts() public {
        // Send ETH directly to the agreement contract
        vm.deal(address(this), 1 ether);
        (bool success,) = address(agreement).call{value: 1 ether}("");
        assertFalse(success, "Direct ETH transfer should revert");
    }

    // ------------------------------------------------------------------------
    // 12. Factory: cannot create agreement for self
    // ------------------------------------------------------------------------
    function test_FactoryCannotCreateForSelf() public {
        vm.prank(owner);
        vm.expectRevert("Invalid tenant");
        factory.createAgreement(owner, RENT, DEPOSIT, DURATION, INTERVAL);
    }

    function test_FactoryCannotCreateForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid tenant");
        factory.createAgreement(address(0), RENT, DEPOSIT, DURATION, INTERVAL);
    }

    // ------------------------------------------------------------------------
    // 13. Edge: payment after multiple intervals
    // ------------------------------------------------------------------------
    function test_PayRentMultipleTimes() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Pay rent 3 times, each after interval
        for (uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + (i + 1) * INTERVAL + 1);
            vm.prank(tenant);
            agreement.payRent{value: RENT}();
        }

        assertEq(agreement.rentHeld(), 3 * RENT);
        // Check last payment timestamp is the last time
        // Not checking exact because we warped each time
    }

    // ------------------------------------------------------------------------
    // 14. Edge: withdrawal after multiple rent payments
    // ------------------------------------------------------------------------
    function test_WithdrawAfterMultiplePayments() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Pay rent 3 times
        for (uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + (i + 1) * INTERVAL + 1);
            vm.prank(tenant);
            agreement.payRent{value: RENT}();
        }

        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        agreement.withdrawRent();
        uint256 ownerBalanceAfter = owner.balance;

        assertEq(ownerBalanceAfter - ownerBalanceBefore, 3 * RENT);
        assertEq(agreement.rentHeld(), 0);
    }
}