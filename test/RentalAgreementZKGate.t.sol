// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ZKAttestation} from "../src/attestation/ZKAttestation.sol";
import {RentalAgreement} from "../src/RentalAgreement.sol";
import {IRentalHistory} from "../src/interfaces/IRentalHistory.sol";
import {GoodRentalHistoryVerifier} from "../src/verifiers/goodRentalHistory/Verifier.sol";
import {KYCProofVerifier} from "../src/verifiers/kYCProof/Verifier.sol";
import {IncomeSufficiencyVerifier} from "../src/verifiers/incomeSufficiency/Verifier.sol";
import {NoDisputesVerifier} from "../src/verifiers/noDisputes/Verifier.sol";

contract RentalHistoryStub is IRentalHistory {
    function recordAgreement(
        address,
        address,
        address,
        uint256,
        uint256,
        uint256
    ) external {}

    function recordActivation(address, uint256) external {}
    function recordPayment(address, uint256, uint256) external {}
    function recordEnd(address, bool) external {}
    function recordDispute(address) external {}

    function getAgreementCount(address) external pure returns (uint256) {
        return 0;
    }

    function getAgreementAt(address, uint256) external pure returns (address) {
        return address(0);
    }
}

contract RentalAgreementZKGateTest is Test {
    ZKAttestation attestation;
    RentalAgreement agreement;

    address constant OWNER  = address(0xA11CE);
    address constant TENANT = address(0xBEEF);

    function setUp() public {
        attestation = new ZKAttestation(
            address(new GoodRentalHistoryVerifier()),
            address(new IncomeSufficiencyVerifier()),
            address(new KYCProofVerifier()),
            address(new NoDisputesVerifier())
        );

        agreement = new RentalAgreement(
            address(new RentalHistoryStub()),
            OWNER,
            TENANT,
            1 ether,      // rentAmount
            2 ether,      // depositAmount
            30 days,      // leaseDuration
            30 days,      // paymentInterval
            address(0),   // no propertyNFT
            0
        );

        vm.prank(OWNER);
        agreement.setZKAttestation(address(attestation));
    }

    function test_SignAsTenant_RevertsWithoutAttestation() public {
        vm.deal(TENANT, 2 ether);
        vm.prank(TENANT);
        vm.expectRevert("ZK attestation required");
        agreement.signAsTenant{value: 2 ether}();
    }

    function test_SignAsTenant_SucceedsAfterAttestation() public {
        bytes memory proof = vm.readFileBinary(
            "./circuits/good_rental_history/target/proof"
        );
        bytes memory raw = vm.readFileBinary(
            "./circuits/good_rental_history/target/public_inputs"
        );
        bytes32[] memory inputs = _decode(raw);

        bytes32 proofType = attestation.GOOD_HISTORY_PROOF();

        vm.prank(TENANT);
        attestation.submitAttestation(
            proofType,
            proof,
            inputs,
            block.timestamp + 365 days
        );

        vm.deal(TENANT, 2 ether);
        vm.prank(TENANT);
        agreement.signAsTenant{value: 2 ether}();

        // State.TenantSigned == 2
        assertEq(uint8(agreement.getStatus()), 2, "state should be TenantSigned");
    }

    function _decode(bytes memory raw) internal pure returns (bytes32[] memory) {
        require(raw.length % 32 == 0, "not multiple of 32");
        bytes32[] memory out = new bytes32[](raw.length / 32);
        for (uint256 i = 0; i < out.length; i++) {
            bytes32 word;
            assembly {
                word := mload(add(add(raw, 0x20), mul(i, 0x20)))
            }
            out[i] = word;
        }
        return out;
    }
}