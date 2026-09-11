// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentStreamToken.sol";
import "../src/RentalHistory.sol";
import "../src/RentalAgreement.sol";
import "../src/RentChainFactory.sol";
import "../src/PropertyNFT.sol";

contract RentStreamTokenTest is Test {
    PropertyNFT public nft;
    RentalHistory public history;
    RentChainFactory public factory;
    RentalAgreement public agreement;
    RentStreamToken public rst;

    address public owner = address(0x1);
    address public tenant = address(0x2);
    address public investorA = address(0x3);
    address public investorB = address(0x4);

    uint256 public tokenId;
    uint256 public constant RENT = 1 ether;
    uint256 public constant DEPOSIT = 2 ether;
    uint256 public constant DURATION = 30 days;
    uint256 public constant INTERVAL = 1 days;
    uint256 public constant FUTURE_RENT = 12 ether; // 12 months tokenized

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(tenant, 100 ether);
        vm.deal(investorA, 100 ether);
        vm.deal(investorB, 100 ether);

        // Property NFT
        nft = new PropertyNFT();
        vm.prank(owner);
        tokenId = nft.registerProperty("ipfs://QmTest");

        // History + Factory + Agreement
        history = new RentalHistory();
        factory = new RentChainFactory(address(history));
        vm.prank(owner);
        agreement = RentalAgreement(
            payable(factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId))
        );

        // Deploy RentStreamToken and link to agreement
        rst = new RentStreamToken("RentChain Stream", "RCS", FUTURE_RENT, address(agreement), owner);

        vm.prank(owner);
        agreement.setRentStreamToken(address(rst));
    }

    // ------------------------------------------------------------------------
    // 1. Tokenization setup
    // ------------------------------------------------------------------------
    function test_TokenizationDeployment() public {
        assertEq(rst.name(), "RentChain Stream");
        assertEq(rst.symbol(), "RCS");
        assertEq(rst.totalSupply(), FUTURE_RENT);
        assertEq(rst.balanceOf(owner), FUTURE_RENT);
        assertEq(rst.rentalAgreement(), address(agreement));
        assertEq(agreement.rentStreamToken(), address(rst));
    }

    function test_CannotSetTokenAfterActivation() public {
        // Activate the agreement
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Try to set token (should fail)
        RentStreamToken bad = new RentStreamToken("X", "X", 1 ether, address(agreement), owner);
        vm.prank(owner);
        vm.expectRevert("Too late to set");
        agreement.setRentStreamToken(address(bad));
    }

    // ------------------------------------------------------------------------
    // 2. Owner sells tokens to investors
    // ------------------------------------------------------------------------
    function _ownerSellsTokens() internal {
        // Owner sends 6 RCS to investorA, 6 RCS to investorB
        vm.prank(owner);
        rst.transfer(investorA, 6 ether);
        vm.prank(owner);
        rst.transfer(investorB, 6 ether);
    }

    // ------------------------------------------------------------------------
    // 3. Rent distribution
    // ------------------------------------------------------------------------
    function test_RentIsForwardedToTokenContract() public {
        _ownerSellsTokens();

        // Activate
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Advance time and pay rent
        vm.warp(block.timestamp + 2 days);
        uint256 rstBalanceBefore = address(rst).balance;
        vm.prank(tenant);
        agreement.payRent{value: RENT}();
        uint256 rstBalanceAfter = address(rst).balance;

        // Rent should have gone to the token contract, not to rentHeld
        assertEq(rstBalanceAfter - rstBalanceBefore, RENT);
        assertEq(agreement.rentHeld(), 0);
    }

    // ------------------------------------------------------------------------
    // 4. Reward math
    // ------------------------------------------------------------------------
    function test_RewardsDistributedProportionally() public {
        _ownerSellsTokens();

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Pay rent once (1 ETH)
        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        // Each investor holds 6 RCS out of 12 total => 0.5 share => 0.5 ETH each
        uint256 earnedA = rst.earned(investorA);
        uint256 earnedB = rst.earned(investorB);
        assertApproxEqAbs(earnedA, 0.5 ether, 10);
        assertApproxEqAbs(earnedB, 0.5 ether, 10);
    }

    function test_MultipleRentPayments() public {
        _ownerSellsTokens();

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // Pay rent 3 times
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + (i + 1) * INTERVAL + 1);
            vm.prank(tenant);
            agreement.payRent{value: RENT}();
        }

        // Total 3 ETH distributed
        // Each investor: 0.5 * 3 = 1.5 ETH
        assertApproxEqAbs(rst.earned(investorA), 1.5 ether, 10);
        assertApproxEqAbs(rst.earned(investorB), 1.5 ether, 10);
    }

    // ------------------------------------------------------------------------
    // 5. Claiming rewards
    // ------------------------------------------------------------------------
    function test_InvestorCanClaim() public {
        _ownerSellsTokens();

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        uint256 balBefore = investorA.balance;
        vm.prank(investorA);
        rst.claimReward();
        uint256 balAfter = investorA.balance;

        assertApproxEqAbs(balAfter - balBefore, 0.5 ether, 10);
        assertEq(rst.earned(investorA), 0);
    }

    function test_CannotClaimZero() public {
        _ownerSellsTokens();
        vm.prank(investorA);
        vm.expectRevert("Nothing to claim");
        rst.claimReward();
    }

    // ------------------------------------------------------------------------
    // 6. Transfer updates rewards correctly
    // ------------------------------------------------------------------------
    function test_TransferSettlesRewards() public {
        _ownerSellsTokens();

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        // First rent payment -> 0.5 ETH each
        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        // InvestorA transfers all tokens to investorB
        vm.prank(investorA);
        rst.transfer(investorB, 6 ether);

        // InvestorA's 0.5 ETH is now in rewards[investorA]
        assertApproxEqAbs(rst.rewards(investorA), 0.5 ether, 10);
        assertEq(rst.balanceOf(investorA), 0);

        // InvestorB now holds 12 RCS
        assertEq(rst.balanceOf(investorB), 12 ether);

        // Second rent payment -> 1 ETH total to investorB (holds all 12)
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        // InvestorB earned: 0.5 (from 1st) + 1.0 (from 2nd) = 1.5 ETH
        assertApproxEqAbs(rst.earned(investorB), 1.5 ether, 10);
        // InvestorA still has 0.5 ETH claimable
        assertApproxEqAbs(rst.earned(investorA), 0.5 ether, 10);
    }

    // ------------------------------------------------------------------------
    // 7. withdrawRent reverts when rent is tokenized
    // ------------------------------------------------------------------------
    function test_OwnerCannotWithdrawWhenTokenized() public {
        _ownerSellsTokens();
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        vm.prank(owner);
        vm.expectRevert("Rent is tokenized");
        agreement.withdrawRent();
    }

    // ------------------------------------------------------------------------
    // 8. Only agreement can call distributeRent
    // ------------------------------------------------------------------------
    function test_OnlyAgreementCanDistribute() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert("Only rental agreement");
        rst.distributeRent{value: 1 ether}();
    }

    // ------------------------------------------------------------------------
    // 9. Direct ETH transfer to token contract reverts
    // ------------------------------------------------------------------------
    function test_DirectETHTransferReverts() public {
        vm.deal(address(this), 1 ether);
        (bool sent,) = address(rst).call{value: 1 ether}("");
        assertFalse(sent, "Direct ETH transfer should revert");
    }
}
