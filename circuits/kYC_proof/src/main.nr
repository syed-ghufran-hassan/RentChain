// Circuit: Prove knowledge of a preimage to an identity commitment.
//
// Binding to a caller is enforced on-chain by ZKAttestation, which checks
// publicInputs[0] == msg.sender before recording an attestation.

use std::hash::pedersen_hash;

fn main(
    // Private
    identity_hash: Field,

    // Public
    tenant_address: pub Field,
    identity_commitment: pub Field,
) {
    let computed = pedersen_hash([identity_hash]);
    assert(computed == identity_commitment);
}

#[test]
fn test_commitment_matches() {
    let identity_hash: Field = 0x1234;
    let tenant_address: Field = 0xBEEF;
    let identity_commitment = pedersen_hash([identity_hash]);

    main(identity_hash, tenant_address, identity_commitment);
}

#[test(should_fail)]
fn test_wrong_commitment_fails() {
    let identity_hash: Field = 0x1234;
    let tenant_address: Field = 0xBEEF;
    let wrong_commitment: Field = 0xdead;

    main(identity_hash, tenant_address, wrong_commitment);
}

#[test]
fn print_commitment() {
    let identity_hash: Field = 0x1234;
    println(pedersen_hash([identity_hash]));
}