// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ZKAttestation} from "../src/attestation/ZKAttestation.sol";
import {GoodRentalHistoryVerifier} from "../src/verifiers/goodRentalHistory/Verifier.sol";
import {KYCProofVerifier} from "../src/verifiers/kYCProof/Verifier.sol";
import {IncomeSufficiencyVerifier} from "../src/verifiers/incomeSufficiency/Verifier.sol";
import {NoDisputesVerifier} from "../src/verifiers/noDisputes/Verifier.sol";

contract ZKAttestationE2ETest is Test {
    ZKAttestation attestation;

    // Choose a tenant address. This must match publicInputs[0] in the proof.
    address constant TENANT = address(0xBEEF);

    function setUp() public {
        attestation = new ZKAttestation(
            address(new GoodRentalHistoryVerifier()),
            address(new IncomeSufficiencyVerifier()),
            address(new KYCProofVerifier()),
            address(new NoDisputesVerifier())
        );
    }

           function test_SubmitNoDisputesProof() public {
        bytes memory proof = vm.readFileBinary(
            "./circuits/no_disputes/target/proof"
        );
        bytes memory raw = vm.readFileBinary(
            "./circuits/no_disputes/target/public_inputs"
        );
        bytes32[] memory inputs = _decode(raw);

        assertEq(
            uint256(inputs[0]),
            uint256(uint160(TENANT)),
            "publicInputs[0] != TENANT"
        );

        bytes32 proofType = attestation.NO_DISPUTES_PROOF();

        vm.prank(TENANT);
        attestation.submitAttestation(
            proofType,
            proof,
            inputs,
            block.timestamp + 365 days
        );

        assertTrue(
            attestation.isVerified(TENANT, proofType),
            "attestation not recorded"
        );
    }

    function test_SubmitGoodHistoryProof() public {
    bytes memory proof = vm.readFileBinary(
        "./circuits/good_rental_history/target/proof"
    );
    bytes memory raw = vm.readFileBinary(
        "./circuits/good_rental_history/target/public_inputs"
    );
    bytes32[] memory inputs = _decode(raw);

    assertEq(
        uint256(inputs[0]),
        uint256(uint160(TENANT)),
        "publicInputs[0] != TENANT; regenerate proof"
    );

    // Evaluate the getter BEFORE prank so the prank applies to submitAttestation.
    bytes32 proofType = attestation.GOOD_HISTORY_PROOF();

    vm.prank(TENANT);
    attestation.submitAttestation(
        proofType,
        proof,
        inputs,
        block.timestamp + 365 days
    );

    assertTrue(
        attestation.isVerified(TENANT, attestation.GOOD_HISTORY_PROOF()),
        "attestation not recorded"
    );
}
    function _decode(bytes memory raw) internal pure returns (bytes32[] memory) {
        require(raw.length % 32 == 0, "not multiple of 32");
        bytes32[] memory out = new bytes32[](raw.length / 32);
        for (uint256 i = 0; i < out.length; i++) {
            bytes32 word;
            assembly { word := mload(add(add(raw, 0x20), mul(i, 0x20))) }
            out[i] = word;
        }
        return out;
    }
}