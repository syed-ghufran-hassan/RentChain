// Circuit: Prove knowledge of a preimage to an identity commitment,
// bound to a specific tenant address.
//
// NOTE: This circuit does NOT verify KYC signatures. It only proves that
// the prover knows `identity_hash` and `secret_key` such that:
//   - pedersen_hash([identity_hash, secret_key]) == identity_commitment
//   - pedersen_hash([secret_key]) == tenant_address
//
// TODO: DO NOT DEPLOY as-is. Real KYC requires an authority signature.

use std::hash::pedersen_hash;

fn main(
    // Private
    identity_hash: Field,
    secret_key: Field,

    // Public
    tenant_address: pub Field,
    identity_commitment: pub Field,
) {
    // 1. Verify identity commitment binds identity_hash + secret_key
    let computed = pedersen_hash([identity_hash, secret_key]);
    assert(computed == identity_commitment);

    // 2. Bind the proof to the tenant address via the secret key
    let tenant_binding = pedersen_hash([secret_key]);
    assert(tenant_binding == tenant_address);
}

#[test]
fn test_commitment_matches() {
    let identity_hash: Field = 0x1234;
    let secret_key: Field = 0xabcdef;
    let tenant_address = pedersen_hash([secret_key]);
    let identity_commitment = pedersen_hash([identity_hash, secret_key]);

    main(identity_hash, secret_key, tenant_address, identity_commitment);
}

#[test(should_fail)]
fn test_wrong_commitment_fails() {
    let identity_hash: Field = 0x1234;
    let secret_key: Field = 0xabcdef;
    let tenant_address = pedersen_hash([secret_key]);
    let wrong_commitment: Field = 0xdead;

    main(identity_hash, secret_key, tenant_address, wrong_commitment);
}

#[test]
fn print_values() {
    let identity_hash: Field = 0x1234;
    let secret_key: Field = 0xabcdef;
    let tenant_address = pedersen_hash([secret_key]);
    let identity_commitment = pedersen_hash([identity_hash, secret_key]);
    println("tenant_address:");
    println(tenant_address);
    println("identity_commitment:");
    println(identity_commitment);
}