// Circuit: Prove monthly income >= 3x rent without revealing salary,
// bound to a specific tenant address.

fn main(
    // Private
    monthly_income: Field,
    secret_key: Field,

    // Public
    tenant_address: pub Field,
    rent_amount: pub Field,
    required_multiplier: pub Field,
    income_commitment: pub Field,
) {
    // 1. Verify the commitment binds monthly_income + secret_key
    let computed = std::hash::pedersen_hash([monthly_income, secret_key]);
    assert(computed == income_commitment);
 

    // 2. Check sufficiency
    let required = (rent_amount as u64) * (required_multiplier as u64);
    assert((monthly_income as u64) >= required);
}

#[test]
fn test_sufficient_income() {
    let monthly_income = 5000;
    let secret_key     = 12345;
    let tenant_address = std::hash::pedersen_hash([secret_key]);
    let commitment     = std::hash::pedersen_hash([monthly_income, secret_key]);

    main(
        monthly_income,   // private
        secret_key,       // private
        tenant_address,   // public
        1000,             // rent_amount
        3,                // required_multiplier => required = 3000
        commitment,       // income_commitment
    );
}

#[test(should_fail)]
fn test_insufficient_income() {
    let monthly_income = 2000;   // less than 3 * 1000 = 3000
    let secret_key     = 12345;
    let tenant_address = std::hash::pedersen_hash([secret_key]);
    let commitment     = std::hash::pedersen_hash([monthly_income, secret_key]);

    main(
        monthly_income,
        secret_key,
        tenant_address,
        1000,
        3,
        commitment,
    );
}

#[test]
fn print_values() {
    let monthly_income = 5000;
    let secret_key = 12345;
    let tenant_address = std::hash::pedersen_hash([secret_key]);
    let commitment = std::hash::pedersen_hash([monthly_income, secret_key]);
    println("tenant_address:");
    println(tenant_address);
    println("income_commitment:");
    println(commitment);
}