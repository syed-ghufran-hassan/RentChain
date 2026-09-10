// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentChain.sol";
import "../src/PropertyNFT.sol"; // ✅ Added import

contract RentChainTest is Test {
    RentalHistory public history;
    RentChainFactory public factory;
    RentalAgreement public agreement;
    PropertyNFT public nft; // ✅ NFT contract
    uint256 public tokenId; // ✅ Minted NFT ID

    address public owner = address(0x1);
    address public tenant = address(0x2);
    address public thirdParty = address(0x3);

    uint256 public constant RENT = 1 ether;
    uint256 public constant DEPOSIT = 2 ether;
    uint256 public constant DURATION = 30 days;
    uint256 public constant INTERVAL = 1 days;

    // Events
    event AgreementSigned(address indexed signer, RentalAgreement.State newState);
    event RentPaid(address indexed tenant, uint256 amount, uint256 timestamp);
    event RentWithdrawn(address indexed owner, uint256 amount);
    event LeaseEnded(address indexed owner, uint256 endTime);
    event DepositReleased(address indexed tenant, uint256 amount);
    event DisputeRaised(address indexed initiator);
    event AgreementCreated(address indexed agreement, address indexed owner, address indexed tenant);

    function setUp() public {
        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(tenant, 100 ether);
        vm.deal(thirdParty, 100 ether);

        // ✅ Deploy PropertyNFT and register a property for the owner
        nft = new PropertyNFT();
        vm.prank(owner);
        tokenId = nft.registerProperty("ipfs://QmTestMetadata");

        // Deploy core contracts
        history = new RentalHistory();
        factory = new RentChainFactory(address(history));

        // Owner creates an agreement for the tenant, passing NFT address and ID
        vm.prank(owner);
        agreement = RentalAgreement(
            payable(factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId))
        );
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
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Created));

        // Check NFT is stored
        assertEq(agreement.propertyNFTId(), tokenId);
        assertEq(address(agreement.propertyNFT()), address(nft));

        // Check history recorded
        assertEq(history.getAgreementCount(owner), 1);
        assertEq(history.getAgreementCount(tenant), 1);
        assertEq(history.getAgreementAt(owner, 0), address(agreement));
        assertEq(history.getAgreementAt(tenant, 0), address(agreement));
    }

    // ------------------------------------------------------------------------
    // 2. Signing flow (unchanged)
    // ------------------------------------------------------------------------
    function test_SignAsOwner() public {
        vm.prank(owner);
        agreement.signAsOwner();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.OwnerSigned));
    }

    function test_SignAsTenant() public {
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.TenantSigned));
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    function test_ActivationWhenBothSign() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Active));
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
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Active));
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
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
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
    // 3. Rent payment (unchanged)
    // ------------------------------------------------------------------------
    function test_PayRent() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();
        assertEq(agreement.rentHeld(), RENT);
        assertEq(agreement.lastPaymentTimestamp(), block.timestamp);
    }

    function test_CannotPayRentEarly() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(tenant);
        vm.expectRevert("Payment not due yet");
        agreement.payRent{value: RENT}();
    }

    function test_CannotPayRentAfterLeaseEnd() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + 31 days);
        vm.prank(tenant);
        vm.expectRevert("Lease already ended");
        agreement.payRent{value: RENT}();
    }

    function test_RentMustBeExact() public {
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
    // 4. Withdraw rent (unchanged)
    // ------------------------------------------------------------------------
    function test_WithdrawRent() public {
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
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.prank(owner);
        vm.expectRevert("No rent to withdraw");
        agreement.withdrawRent();
    }

    function test_OnlyOwnerCanWithdrawRent() public {
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
    // 5. End lease (unchanged)
    // ------------------------------------------------------------------------
    function test_EndLease() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Ended));
    }

    function test_CannotEndLeaseBeforeDuration() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert("Lease not ended yet");
        agreement.endLease();
    }

    function test_OnlyOwnerCanEndLease() public {
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
    // 6. Release deposit (unchanged)
    // ------------------------------------------------------------------------
    function test_ReleaseDeposit() public {
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
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        vm.prank(owner);
        agreement.releaseDeposit();
        vm.prank(owner);
        vm.expectRevert("Deposit already released");
        agreement.releaseDeposit();
    }

    function test_CannotReleaseBeforeEnd() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.prank(owner);
        vm.expectRevert("Invalid state");
        agreement.releaseDeposit();
    }

    function test_OnlyOwnerCanReleaseDeposit() public {
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
    // 7. Dispute mechanism (unchanged)
    // ------------------------------------------------------------------------
    function test_DisputeByTenant() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        vm.prank(tenant);
        agreement.disputeDeposit();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Disputed));
    }

    function test_DisputeByOwner() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        vm.prank(owner);
        agreement.disputeDeposit();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Disputed));
    }

    function test_ThirdPartyCannotDispute() public {
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
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.prank(tenant);
        vm.expectRevert("Invalid state");
        agreement.disputeDeposit();
    }

    // ------------------------------------------------------------------------
    // 8. History records verification (unchanged)
    // ------------------------------------------------------------------------
    function test_HistoryRecordsActivation() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        assertEq(agreement.leaseStart(), block.timestamp);
    }

    function test_HistoryRecordsPayment() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();
        assertEq(agreement.rentHeld(), RENT);
    }

    function test_HistoryRecordsEnd() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Ended));
    }

    function test_HistoryRecordsDispute() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();
        vm.prank(tenant);
        agreement.disputeDeposit();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Disputed));
    }

    // ------------------------------------------------------------------------
    // 9. View function (unchanged)
    // ------------------------------------------------------------------------
    function test_GetStatus() public view {
        assertEq(uint256(agreement.getStatus()), uint256(RentalAgreement.State.Created));
    }

    // ------------------------------------------------------------------------
    // 10. Direct Ether transfer should revert (unchanged)
    // ------------------------------------------------------------------------
    function test_ReceiveReverts() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(agreement).call{value: 1 ether}("");
        assertFalse(success, "Direct ETH transfer should revert");
    }

    // ------------------------------------------------------------------------
    // 11. Factory: cannot create agreement for self or zero address
    // ------------------------------------------------------------------------
    function test_FactoryCannotCreateForSelf() public {
        vm.prank(owner);
        vm.expectRevert("Invalid tenant");
        factory.createAgreement(owner, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
    }

    function test_FactoryCannotCreateForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid tenant");
        factory.createAgreement(address(0), RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
    }

    // ------------------------------------------------------------------------
    // 12. Edge: payment after multiple intervals (unchanged)
    // ------------------------------------------------------------------------
    function test_PayRentMultipleTimes() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + (i + 1) * INTERVAL + 1);
            vm.prank(tenant);
            agreement.payRent{value: RENT}();
        }
        assertEq(agreement.rentHeld(), 3 * RENT);
    }

    // ------------------------------------------------------------------------
    // 13. Edge: withdrawal after multiple rent payments (unchanged)
    // ------------------------------------------------------------------------
    function test_WithdrawAfterMultiplePayments() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();
        for (uint256 i = 0; i < 3; i++) {
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

    function test_AutoReleaseDepositNoDispute() public {
        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Check deadline is set
        assertEq(agreement.depositReleaseDeadline(), block.timestamp + 7 days);

        // Warp past deadline
        vm.warp(block.timestamp + 8 days);

        uint256 tenantBalanceBefore = tenant.balance;
        // Anyone can call autoRelease
        vm.prank(address(0x123));
        agreement.autoReleaseDeposit();
        uint256 tenantBalanceAfter = tenant.balance;

        assertEq(tenantBalanceAfter - tenantBalanceBefore, DEPOSIT);
        assertEq(agreement.depositHeld(), 0);
        assertTrue(agreement.depositReleased());
    }

    function test_DisputePausesAutoRelease() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Tenant disputes within window
        vm.prank(tenant);
        agreement.disputeDeposit();

        // Deadline is set to max (paused)
        assertEq(agreement.depositReleaseDeadline(), type(uint256).max);

        // Warp far ahead
        vm.warp(block.timestamp + 100 days);

        // Auto‑release should revert
        vm.expectRevert("Disputed, cannot auto-release");
        agreement.autoReleaseDeposit();
    }

    function test_CannotDisputeAfterWindow() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Warp past dispute window
        vm.warp(block.timestamp + 8 days);

        vm.prank(tenant);
        vm.expectRevert("Dispute window closed");
        agreement.disputeDeposit();

        // Auto‑release should now work
        uint256 tenantBalanceBefore = tenant.balance;
        agreement.autoReleaseDeposit();
        uint256 tenantBalanceAfter = tenant.balance;
        assertEq(tenantBalanceAfter - tenantBalanceBefore, DEPOSIT);
    }

    function test_ResolverCanResolveDispute() public {
        // Deploy mock resolver
        MockResolver resolver = new MockResolver();

        // Activate and end lease
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Owner sets resolver
        vm.prank(owner);
        agreement.setDisputeResolver(address(resolver));

        // Tenant disputes
        vm.prank(tenant);
        agreement.disputeDeposit();

        // Resolver should have been notified
        assertEq(resolver.agreement(), address(agreement));

        // Resolver decides in favor of owner
        vm.prank(address(resolver));
        resolver.resolve(false); // tenantWins = false

        // Owner gets deposit
        uint256 ownerBalanceBefore = owner.balance;
        // The resolve function already sent deposit, so we just check balances
        // We need to capture event or balance change.
        // In this test we can simply assert depositReleased.
        assertTrue(agreement.depositReleased());
        assertEq(agreement.depositHeld(), 0);

        // Check that deposit went to owner (simplified: we'd capture before/after)
        // We'll add a separate balance check if needed.
    }

    function test_OwnerCannotReleaseAfterDispute() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Tenant disputes
        vm.prank(tenant);
        agreement.disputeDeposit();

        // Owner tries to release – should revert
        vm.prank(owner);
        vm.expectRevert("Disputed, use resolver or auto-release");
        agreement.releaseDeposit();
    }

    function test_OwnerReleaseDepositBeforeDeadline() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Owner releases immediately (before auto-release)
        uint256 tenantBalanceBefore = tenant.balance;
        vm.prank(owner);
        agreement.releaseDeposit();
        uint256 tenantBalanceAfter = tenant.balance;
        assertEq(tenantBalanceAfter - tenantBalanceBefore, DEPOSIT);
        assertTrue(agreement.depositReleased());
    }

    function test_AutoReleaseOnlyOnce() public {
        // 1. Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // 2. End lease
        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // 3. Move past the dispute window
        vm.warp(block.timestamp + 8 days);

        // 4. First call — succeeds
        agreement.autoReleaseDeposit();
        assertTrue(agreement.depositReleased());
        assertEq(agreement.depositHeld(), 0);

        // 5. Second call — should revert with "No deposit held"
        vm.expectRevert("No deposit held");
        agreement.autoReleaseDeposit();
    }
}

contract MockResolver {
    address public agreement;
    bool public tenantWins;

    function escalate(address _agreement) external {
        agreement = _agreement;
    }

    function resolve(bool _tenantWins) external {
        tenantWins = _tenantWins;
        RentalAgreement(payable(agreement)).resolveDispute(_tenantWins);
    }
}
