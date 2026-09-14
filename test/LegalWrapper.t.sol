// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LegalWrapper.sol";

contract LegalWrapperTest is Test {
    LegalWrapper public wrapper;

    address public owner = address(0x1);
    address public tenant = address(0x2);
    address public stranger = address(0x3);

    address public agreement = address(0xAA);
    bytes32 public constant DOC_HASH = keccak256("signed-lease-pdf");

    event DocumentAnchored(address indexed agreement, bytes32 documentHash, string jurisdiction, address indexed by);
    event DisputeEscalated(address indexed agreement, uint256 caseId);

    function setUp() public {
        wrapper = new LegalWrapper();
    }

    // ------------------------------------------------------------------------
    // 1. Anchoring
    // ------------------------------------------------------------------------
    function test_AnchorDocumentSuccess() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        assertEq(wrapper.getDocumentHash(agreement), DOC_HASH);
        assertFalse(wrapper.isEscalated(agreement));
        assertEq(wrapper.anchoredBy(agreement), owner);
    }

    function test_AnchorEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(wrapper));
        emit DocumentAnchored(agreement, DOC_HASH, "US-CA", owner);

        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");
    }

    function test_AnchorRevertsOnZeroAgreement() public {
        vm.prank(owner);
        vm.expectRevert("Invalid agreement");
        wrapper.anchorDocument(address(0), DOC_HASH, "US-CA");
    }

    function test_AnchorRevertsOnZeroHash() public {
        vm.prank(owner);
        vm.expectRevert("Invalid hash");
        wrapper.anchorDocument(agreement, bytes32(0), "US-CA");
    }

    function test_AnchorRevertsOnEmptyJurisdiction() public {
        vm.prank(owner);
        vm.expectRevert("Invalid jurisdiction");
        wrapper.anchorDocument(agreement, DOC_HASH, "");
    }

    function test_AnchorMultipleAgreements() public {
        address agreement2 = address(0xBB);
        bytes32 hash2 = keccak256("second-lease");

        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        vm.prank(owner);
        wrapper.anchorDocument(agreement2, hash2, "EU-DE");

        assertEq(wrapper.getDocumentHash(agreement), DOC_HASH);
        assertEq(wrapper.getDocumentHash(agreement2), hash2);
    }

    // ------------------------------------------------------------------------
    // 2. Update by original anchorer
    // ------------------------------------------------------------------------
    function test_OriginalAnchorerCanUpdate() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        bytes32 newHash = keccak256("signed-lease-v2");
        vm.prank(owner);
        wrapper.anchorDocument(agreement, newHash, "US-NY");

        assertEq(wrapper.getDocumentHash(agreement), newHash);
    }

    function test_StrangerCannotUpdate() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        bytes32 newHash = keccak256("malicious");
        vm.prank(stranger);
        vm.expectRevert("Not authorized");
        wrapper.anchorDocument(agreement, newHash, "XX-XX");
    }

    // ------------------------------------------------------------------------
    // 3. Escalation
    // ------------------------------------------------------------------------
    function test_RecordEscalationSuccess() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        wrapper.recordEscalation(agreement, 42);

        assertTrue(wrapper.isEscalated(agreement));
        (,,, bool esc, uint256 caseId) = wrapper.docs(agreement);
        assertTrue(esc);
        assertEq(caseId, 42);
    }

    function test_RecordEscalationEmitsEvent() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        vm.expectEmit(true, false, false, true, address(wrapper));
        emit DisputeEscalated(agreement, 42);
        wrapper.recordEscalation(agreement, 42);
    }

    function test_EscalateWithoutAnchorReverts() public {
        vm.expectRevert("Agreement not anchored");
        wrapper.recordEscalation(agreement, 1);
    }

    function test_CannotEscalateTwice() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        wrapper.recordEscalation(agreement, 1);

        vm.expectRevert("Already escalated");
        wrapper.recordEscalation(agreement, 2);
    }

    // ------------------------------------------------------------------------
    // 4. Escalated flag preserved on document update
    // ------------------------------------------------------------------------
    function test_EscalationPreservedAfterUpdate() public {
        vm.prank(owner);
        wrapper.anchorDocument(agreement, DOC_HASH, "US-CA");

        wrapper.recordEscalation(agreement, 42);

        // Anchorer updates the doc — escalation flag must persist
        bytes32 newHash = keccak256("updated-lease");
        vm.prank(owner);
        wrapper.anchorDocument(agreement, newHash, "US-NY");

        assertTrue(wrapper.isEscalated(agreement));
        (,,, bool esc, uint256 caseId) = wrapper.docs(agreement);
        assertTrue(esc);
        assertEq(caseId, 42);
        assertEq(wrapper.getDocumentHash(agreement), newHash);
    }

    // ------------------------------------------------------------------------
    // 5. View helpers
    // ------------------------------------------------------------------------
    function test_GetDocumentHashEmpty() public view {
        assertEq(wrapper.getDocumentHash(agreement), bytes32(0));
    }

    function test_IsEscalatedDefaultFalse() public view {
        assertFalse(wrapper.isEscalated(agreement));
    }
}