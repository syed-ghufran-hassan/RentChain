// Circuit: Prove tenant has no unresolved disputes.

fn main(
    // Private
    dispute_flags: [Field; 10],
    secret_key: Field,
    
    // Public
    tenant_address: pub Field,
    dispute_commitment: pub Field,
) {
    // 1. Verify commitment
    let computed = std::hash::pedersen_hash([
        std::hash::pedersen_hash(dispute_flags),
        secret_key
    ]);
    assert(computed == dispute_commitment);
    
    // 2. Assert no disputes
    let mut total = 0;
    for i in 0..10 {
        total += dispute_flags[i];
    }
    assert(total == 0);
}

#[test]
fn test_no_disputes() {
    let dispute_flags: [Field; 10] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let secret_key = 12345;

    // Commit to the hashed flags + secret, exactly as the circuit does
    let commitment = std::hash::pedersen_hash([
        std::hash::pedersen_hash(dispute_flags),
        secret_key,
    ]);

    main(dispute_flags, secret_key, 0, commitment);
}

#[test(should_fail)]
fn test_has_dispute() {
    
    let dispute_flags: [Field; 10] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let secret_key = 12345;

    let commitment = std::hash::pedersen_hash([
        std::hash::pedersen_hash(dispute_flags),
        secret_key,
    ]);

    main(dispute_flags, secret_key, 0, commitment);
}

#[test]
fn print_commitment() {
    let dispute_flags: [Field; 10] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let secret_key = 12345;
    let commitment = std::hash::pedersen_hash([
        std::hash::pedersen_hash(dispute_flags),
        secret_key
    ]);
    println(commitment);
}