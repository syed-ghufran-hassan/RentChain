use std::hash::pedersen_hash;

global MAX_RENTALS: u32 = 5;

fn main(
    past_agreements: [Field; MAX_RENTALS],
    outcomes: [Field; MAX_RENTALS],
    secret_key: Field,
    tenant_address: pub Field,
    threshold: pub Field,
    merkle_root: pub Field,
) {
    let mut leaves: [Field; MAX_RENTALS] = [0; MAX_RENTALS];
    for i in 0..MAX_RENTALS {
        if (past_agreements[i] as u64) != 0 {
            leaves[i] = pedersen_hash([past_agreements[i], outcomes[i]]);
        }
    }

    let computed_root = compute_merkle_root(leaves);
    assert(computed_root == merkle_root);

    let mut success_count: u64 = 0;
    for i in 0..MAX_RENTALS {
        if ((past_agreements[i] as u64) != 0) & ((outcomes[i] as u64) == 1) {
            success_count += 1;
        }
    }

    assert(success_count >= (threshold as u64));
}

fn compute_merkle_root(leaves: [Field; MAX_RENTALS]) -> Field {
    // Pad to 8 (next power of 2 above MAX_RENTALS = 5)
    let mut padded: [Field; 8] = [0; 8];
    for i in 0..MAX_RENTALS {
        padded[i] = leaves[i];
    }

    // Level 1: 8 -> 4
    let mut level1: [Field; 4] = [0; 4];
    for i in 0..4 {
        level1[i] = pedersen_hash([padded[2 * i], padded[2 * i + 1]]);
    }

    // Level 2: 4 -> 2
    let mut level2: [Field; 2] = [0; 2];
    for i in 0..2 {
        level2[i] = pedersen_hash([level1[2 * i], level1[2 * i + 1]]);
    }

    // Level 3: 2 -> 1 (root)
    pedersen_hash([level2[0], level2[1]])
}

// ---------------------------------------------
// Helpers + tests
// ---------------------------------------------

fn build_leaves(
    past_agreements: [Field; MAX_RENTALS],
    outcomes: [Field; MAX_RENTALS],
) -> [Field; MAX_RENTALS] {
    let mut leaves: [Field; MAX_RENTALS] = [0; MAX_RENTALS];
    for i in 0..MAX_RENTALS {
        if (past_agreements[i] as u64) != 0 {
            leaves[i] = pedersen_hash([past_agreements[i], outcomes[i]]);
        }
    }
    leaves
}

#[test]
fn test_good_history_passes() {
    let past_agreements: [Field; MAX_RENTALS] = [1, 2, 3, 4, 5];
    let outcomes:        [Field; MAX_RENTALS] = [1, 1, 1, 1, 1];

    let leaves = build_leaves(past_agreements, outcomes);
    let root   = compute_merkle_root(leaves);

    main(past_agreements, outcomes, 0, 0, 5, root);
}

#[test(should_fail)]
fn test_bad_history_fails() {
    // Only 2 successes, but threshold is 5 -- should fail the assert
    let past_agreements: [Field; MAX_RENTALS] = [1, 2, 3, 4, 5];
    let outcomes:        [Field; MAX_RENTALS] = [1, 1, 0, 0, 0];

    let leaves = build_leaves(past_agreements, outcomes);
    let root   = compute_merkle_root(leaves);

    main(past_agreements, outcomes, 0, 0, 5, root);
}

#[test]
fn print_root() {
    let past_agreements: [Field; MAX_RENTALS] = [1, 2, 3, 4, 5];
    let outcomes:        [Field; MAX_RENTALS] = [1, 1, 1, 1, 1];
    let leaves = build_leaves(past_agreements, outcomes);
    let root = compute_merkle_root(leaves);
    println(root);
}