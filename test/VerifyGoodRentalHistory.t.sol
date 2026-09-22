// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {GoodRentalHistoryVerifier} from "../src/verifiers/goodRentalHistory/Verifier.sol";

contract VerifyGoodRentalHistoryTest is Test {
    function test_ProofVerifiesOnChain() public {
        GoodRentalHistoryVerifier v = new GoodRentalHistoryVerifier();

        bytes memory proof = vm.readFileBinary(
            "./circuits/good_rental_history/target/proof"
        );
        bytes memory rawInputs = vm.readFileBinary(
            "./circuits/good_rental_history/target/public_inputs"
        );

        require(rawInputs.length % 32 == 0, "public_inputs not multiple of 32");
        bytes32[] memory inputs = new bytes32[](rawInputs.length / 32);
        for (uint256 i = 0; i < inputs.length; i++) {
            bytes32 word;
            assembly {
                word := mload(add(add(rawInputs, 0x20), mul(i, 0x20)))
            }
            inputs[i] = word;
        }

        bool ok = v.verify(proof, inputs);
        assertTrue(ok, "proof did not verify on-chain");
    }
}