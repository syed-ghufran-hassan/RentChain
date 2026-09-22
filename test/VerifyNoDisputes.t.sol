// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {NoDisputesVerifier} from "../src/verifiers/noDisputes/Verifier.sol";

contract VerifyNoDisputesTest is Test {
    function test_ProofVerifiesOnChain() public {
        NoDisputesVerifier v = new NoDisputesVerifier();

        bytes memory proof = vm.readFileBinary(
            "./circuits/no_disputes/target/proof"
        );
        bytes memory rawInputs = vm.readFileBinary(
            "./circuits/no_disputes/target/public_inputs"
        );

        bytes32[] memory inputs = _decode(rawInputs);
        bool ok = v.verify(proof, inputs);
        assertTrue(ok, "proof did not verify on-chain");
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