# RentChain
 

**RentChain** is a decentralized rental agreement orchestrator built on Ethereum. It automates the entire rental lifecycle—from signing and escrow to rent collection, lease termination, and dispute recording—using smart contracts. All transactions and rental history are stored immutably on-chain, providing transparency and building reputation for both tenants and property owners.

---

## 🚀 Key Features

- **Trustless Agreements** – Rental terms (rent, deposit, duration, payment schedule) are encoded in smart contracts.
- **Escrow Service** – Security deposits are held in the contract and released only when conditions are met.
- **Automated Payments** – Tenants pay rent on a fixed schedule; owners can withdraw accumulated rent at any time.
- **Immutable Rental History** – Every agreement, payment, activation, and dispute is recorded via the `RentalHistory` contract.
- **Ethereum Address Authentication** – No emails or passwords; users authenticate with their wallet.
- **Dispute Mechanism** – Parties can flag a dispute on-chain, which is immediately recorded in the history.
- **Factory Pattern** – New rental agreements are deployed via a factory, ensuring clean deployment and easy tracking.
- **Property Tokenization (ERC‑721)** – Every property is minted as an NFT, giving on‑chain proof of title or leasehold rights. Only the NFT holder can create a rental agreement for that property.
- **Time‑Locked Escrow** – After the lease ends, a 7‑day dispute window starts. If no dispute is raised, anyone can trigger `autoReleaseDeposit()` to return the deposit to the tenant automatically.
- **Optional Dispute Resolver** – A DAO or multisig can be plugged in as the dispute resolver. When a dispute is raised, the resolver is notified and can settle the deposit via `resolveDispute(bool tenantWins)`.
- **Yield Tokenization (ERC‑20)** – Owners can tokenize a future rent stream into `RentStreamToken`. Investors buy tokens and receive a proportional share of each rent payment. The owner gains upfront liquidity, and investors earn a yield.
- **Oracle‑Assisted Deposit Release** – A Chainlink Functions oracle can release the deposit early when an off-chain inspection passes. Cannot override an open dispute.
- **Legal Wrapper + DAO Arbitration** – Each agreement's signed lease is anchored on-chain via IPFS hash and jurisdiction. Disputes escalate to a Kleros-compatible arbitrator that rules on the deposit release.
- **DeFi Lending** – Property owners can use `PropertyNFT` as collateral to borrow stablecoins. Loans accrue 10% APR; positions above the 75% liquidation threshold can be liquidated by anyone.
- **Zero-Knowledge Tenant Screening (Noir)** – Tenants prove eligibility on-chain without revealing raw data. Four UltraHonk circuits (`good_rental_history`, `income_sufficiency`, `kYC_proof`, `no_disputes`) generate proofs off-chain; `ZKAttestation` verifies them on-chain and records a per-tenant attestation. `RentalAgreement.signAsTenant()` is gated on a valid `good_history` proof — no trusted signer, no ECDSA. *(Sepolia deployment deferred — see Known Limitations.)*

---

## 🏗️ Architecture

The system consists of fourteen core contracts:

| Contract | Purpose |
|----------|---------|
| **PropertyNFT** | ERC‑721 that represents property titles or leasehold rights. Mints an NFT per property with metadata (IPFS/Arweave). |
| **RentalHistory** | Stores immutable records of all agreements, payments, and events per user. Implements the `IRentalHistory` interface. |
| **RentalAgreement** | Handles the full rental lifecycle: signing, escrow, rent payments, lease end, time‑locked deposit release, and disputes. Uses OpenZeppelin's `ReentrancyGuard`. |
| **RentChainFactory** | Deploys new `RentalAgreement` instances, verifies NFT ownership, and registers agreements in `RentalHistory`. |
| **RentStreamToken** | ERC‑20 that represents a share of a future rent stream. Uses a reward‑per‑token accumulator to distribute rent to holders proportionally. |
| **RentalOracle** | Chainlink Functions consumer. After lease end, queries an off-chain inspection API and calls `releaseDepositByOracle()` if the inspection passed. |
| **LegalWrapper** | Anchors signed lease documents (IPFS hash + jurisdiction) to each agreement and tracks escalation status. |
| **KlerosResolver** | Implements `IDisputeResolver`. Opens a Kleros arbitration on dispute; on ruling, calls `RentalAgreement.resolveDispute(bool)`. |
| **RentChainLending** | Collateralized lending pool. Accepts `PropertyNFT` as collateral, lends stablecoins up to a 50% LTV, and liquidates positions above the 75% liquidation threshold. |
| **ZKAttestation** | Verifies UltraHonk proofs on-chain, records per-tenant attestations, exposes `isVerified(tenant, proofType)`. |
| **GoodRentalHistoryVerifier** | `bb`-generated Solidity verifier for the `good_rental_history` circuit. |
| **IncomeSufficiencyVerifier** | `bb`-generated verifier for `income_sufficiency`. |
| **KYCProofVerifier** | `bb`-generated verifier for `kYC_proof`. |
| **NoDisputesVerifier** | `bb`-generated verifier for `no_disputes`. |
> **ZK note:** the four UltraHonk verifiers (`GoodRentalHistoryVerifier`, `IncomeSufficiencyVerifier`, `KYCProofVerifier`, `NoDisputesVerifier`) are compiled and tested, but exceed Ethereum's EIP-170 code-size limit at ~33 KB each. See *Known Limitations*.

## 🔄 Rental Lifecycle

1. **Owner registers property** → mints a `PropertyNFT` via `registerProperty(metadataURI)`.
2. **Owner creates agreement** → calls `RentChainFactory.createAgreement(...)` passing the NFT address and token ID. The factory verifies NFT ownership and deploys a new `RentalAgreement`.
3. **Both parties sign** → `signAsOwner()` and `signAsTenant()` (deposit sent in ETH). Lease becomes `Active`.
4. **Tenant pays rent** → `payRent()` each `paymentInterval`.
5. **Owner withdraws rent** → `withdrawRent()` anytime while active.
6. **Lease ends** → owner calls `endLease()`. This starts a **7‑day dispute window**.
7. **Inspection (optional)** → owner requests an off-chain inspection via `RentalOracle`. If it passes, `releaseDepositByOracle()` releases the deposit to the tenant early — this **cannot** override a dispute.
8. **Happy path** → if no oracle and no dispute, anyone calls `autoReleaseDeposit()` after the 7-day window → deposit goes to tenant.
9. **Dispute path** → either party calls `disputeDeposit()` during the window. The timer pauses and the `disputeResolver` (if set) is notified.
10. **Resolver settles** → the resolver calls `resolveDispute(bool tenantWins)` → deposit goes to the winner. When the resolver is a Kleros adapter, this follows a full arbitration: `LegalWrapper.anchorDocument(...)` stores the lease hash → `disputeDeposit()` escalates to Kleros → the arbitrator's ruling triggers `resolveDispute(bool)`.
11. **Timeout fallback** → if the resolver is silent for 30 days after a dispute is raised, anyone can call `finalizeDispute()` and the deposit goes to the tenant by default.
> **Resolver & oracle freeze:** `setDisputeResolver()` and `setOracle()` can only be called while the agreement is in the `Created` state. Once either party signs, both are locked — this prevents late appointment of a resolver that could bias an ongoing dispute.

## 💰 Yield Tokenization

Owners can sell future rent cash flows as ERC‑20 tokens:

1. Owner deploys `RentStreamToken(name, symbol, totalFutureRent, agreementAddress, ownerAddress)`.
2. Owner calls `RentalAgreement.setRentStreamToken(tokenAddress)` **before both parties sign**.
3. Owner transfers tokens to investors.
4. Each `payRent()` call forwards rent directly to the token contract, which updates the reward accumulator.
5. Investors call `RentStreamToken.claimReward()` to withdraw their share.

 
>  **Note on rounding:** because Solidity integer division truncates, `rewardPerTokenStored` accrues tiny rounding dust (a few wei per payment). The dust stays in the token contract; it does not affect any individual holder materially.
 

**Reward accumulator (updated on each rent payment):**

$$
rewardPerTokenStored \mathrel{+}= \frac{rentPaid \times 10^{18}}{totalSupply}
$$

**Holder's claimable amount (view function):**

$$
earned(h) = \frac{balanceOf(h) \times (rewardPerTokenStored - userRewardPerTokenPaid[h])}{10^{18}} + rewards[h]
$$

**On claim or transfer, the holder's snapshot is updated:**

$$
userRewardPerTokenPaid[h] = rewardPerTokenStored \quad\quad rewards[h] = 0
$$

## ⚖️ Legal Wrapper + DAO Arbitration

Every agreement can be anchored to its off-chain lease document, and disputes can be escalated to a decentralized arbitrator.

1. **Anchor the lease** — the owner calls `LegalWrapper.anchorDocument(agreement, docHash, jurisdiction)`. The hash points to an IPFS-stored PDF; the jurisdiction records the applicable legal system (e.g., `US-CA`).
2. **Wire the resolver** — before signing, the owner sets `RentalAgreement.disputeResolver = KlerosResolver`.
3. **Fund the fee pool** — anyone can call `KlerosResolver.fundFeePool()` to cover arbitration costs (~0.01 ETH per dispute).
4. **Dispute** — on `disputeDeposit()`, the agreement calls `KlerosResolver.escalate(agreement)`, which:
   - Verifies the document is anchored.
   - Opens a Kleros dispute with `choices = 2` (`[owner wins, tenant wins]`).
   - Records the case in `LegalWrapper` (`escalated = true`).
5. **Ruling** — the arbitrator calls `KlerosResolver.rule(disputeId, ruling)`. The resolver forwards the outcome via `RentalAgreement.resolveDispute(tenantWins)`.
6. **Release** — the deposit goes to the winner. The default 30-day timeout fallback still applies if the arbitrator never rules.

> **Why this matters:** the on-chain agreement is now tied to a signed legal document. Disputes are resolved by a neutral third party (Kleros), not by the property owner — closing the trust gap that a time-lock alone can't.

### Contracts

| Contract | Purpose |
|----------|---------|
| **LegalWrapper** | Stores IPFS hash + jurisdiction per agreement; tracks whether a dispute was escalated. |
| **KlerosResolver** | Adapter that implements `IDisputeResolver` and bridges RentChain to a Kleros-compatible arbitrator. |
| **IArbitrator** | Minimal interface for the arbitrator (create dispute, quote cost). |

## 🏦 DeFi Lending

Property owners can unlock liquidity without selling by borrowing against their tokenized real estate.

1. **Deposit collateral** — the owner approves the lending contract, then calls `depositCollateral(tokenId, appraisedValue)`. The `PropertyNFT` is transferred into the pool.
2. **Borrow** — up to **50% LTV** (`maxBorrow = collateralValue × 5000 / 10000`). Loan tokens (USDC) are transferred to the borrower.
3. **Accrue interest** — simple 10% APR, per-second. `currentDebt(tokenId)` returns principal + accrued interest − repaid.
4. **Repay** — the borrower approves USDC and calls `repay(tokenId, amount)`. Once debt = 0, the loan is closed.
5. **Withdraw** — the borrower calls `withdrawCollateral(tokenId)` and receives the NFT back.
6. **Liquidate** — if `currentLtvBps(tokenId) ≥ 7500` (75%), anyone can call `liquidate(tokenId)`. The liquidator repays the debt + a 10% penalty and receives the NFT.

### Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| **LTV** | 50% | Max borrow as a fraction of the appraisal |
| **Liquidation threshold** | 75% | Debt/collateral ratio at which liquidation is allowed |
| **Liquidation penalty** | 10% | Added to debt paid by the liquidator |
| **Interest rate** | 10% APR | Simple, per-second accrual |
| **Loan asset** | USDC | Circle-issued USDC on Sepolia |

> **Note on appraisal:** in V1, the collateral value is set by the borrower at deposit time (for demo purposes). Production would use an oracle or a DAO appraiser.

### 🚫 Guaranteed Failure Paths

| Action | Reverts with |
|--------|--------------|
| Non‑owner calls `signAsOwner()` | `"Not owner"` |
| Non‑tenant calls `signAsTenant()` | `"Not tenant"` |
| Tenant sends wrong deposit amount | `"Must send exact deposit amount"` |
| Tenant pays rent before interval | `"Payment not due yet"` |
| Owner ends lease early | `"Lease not ended yet"` |
| Anyone disputes after the 7‑day window | `"Dispute window closed"` |
| Owner tries to override a dispute | `"Disputed, use resolver or auto-release"` |
| Oracle tries to act after window | `"Window closed"` |
| Oracle tries to act during a dispute | `"Invalid state"` |
| Resolver tries to act after timeout | `"Timeout passed, use finalizeDispute"` |
| Owner sets resolver after signing | `"Resolver frozen after signing"` |
| Owner sets oracle after signing | `"Oracle frozen after signing"` |
| Escalate dispute without anchored document | `"Agreement not anchored"` |
| Escalate when fee pool is empty | `"Insufficient fee pool"` |
| Non-arbitrator calls `rule()` | `"Only arbitrator"` |
| Arbitrator rules twice on the same dispute | `"Already ruled"` |
| Stranger updates an anchored document | `"Not authorized"` |
| Anchor with zero hash | `"Invalid hash"` |
| Anchor with empty jurisdiction | `"Invalid jurisdiction"` |
| Escalate same agreement twice | `"Already escalated"` |
| Non-owner calls `fundPool()` | `"OwnableUnauthorizedAccount"` |
| Deposit an NFT you don't own | `"Not NFT owner"` |
| Deposit an already-locked NFT | `"Already locked"` |
| Borrow more than LTV allows | `"Exceeds LTV"` |
| Borrow when the loan is already active | `"Loan active"` |
| Borrow more than the pool holds | `"Insufficient pool liquidity"` |
| Repay a non-existent loan | `"No active loan"` |
| Non-borrower calls `repay()` | `"Not borrower"` |
| Non-borrower calls `withdrawCollateral()` | `"Not borrower"` |
| Withdraw while loan is active | `"Loan still active"` |
| Liquidate a healthy loan | `"Not liquidatable"` |
| Liquidate with insufficient USDC | `"Payment failed"` |
| Tenant signs without a `good_history` attestation | `"ZK attestation required"` |
| Attestation submitted with a proof bound to a different address | `"Proof not bound to sender"` |
| Attestation submitted with an invalid or stale proof | `"Invalid proof"` |
| Attestation submitted after its expiry | `"Already expired"` |
| Owner sets ZK attestation after signing | `"Frozen after signing"` |

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Development with Foundry
 
### Build

```shell
$ forge build
```

### Test

```shell
$ forge test -vv
$ forge test --match-contract PropertyNFTTest -vv
$ forge test --match-test test_ResolverCanResolveDispute -vv
$ forge test --match-contract RentStreamTokenTest -vv
$ forge test --match-contract LegalWrapperTest -vv
$ forge test --match-contract KlerosResolverTest -vv
$ forge test --match-contract RentalOracleTest -vv
$ forge test --match-contract RentChainLendingTest -vv
$ forge test --match-pattern "Verify.*Test" -vv          # standalone verifier tests (4)
$ forge test --match-contract ZKAttestationE2ETest -vv   # submitAttestation per proof type (4)
$ forge test --match-contract RentalAgreementZKGateTest -vv  # gate reverts/succeeds (2)

```

### Gas Report

```shell
$ forge test --gas-report
``` 


### Format

```shell
$ forge fmt
```



### Gas Snapshots

```shell
$ forge snapshot
```
 

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
 

## Implementation Roadmap

### ✅ Phase 1: Property Tokenization (Completed)

- [x] Deployed `PropertyNFT` on Sepolia.
- [x] Integrated with `RentChainFactory` (verifies NFT ownership).
- [x] Updated `RentalAgreement` to reference NFT ID via `propertyNFTId`.
- [x] Added time-locked escrow + optional dispute resolver + 30-day timeout fallback.

### ✅ Phase 2: Yield Tokenization (Completed)

- [x] Deployed `RentStreamToken` on Sepolia.
- [x] Linked to `RentalAgreement` via `setRentStreamToken`.
- [x] `payRent()` forwards rent to the token contract; holders claim via `claimReward()`.

### ✅ Phase 3: Oracle Integration (Completed)

- [x] Deployed `RentalOracle` on Sepolia.
- [x] Integrated Chainlink Functions to fetch inspection results.
- [x] `RentalAgreement.releaseDepositByOracle()` callable only by oracle, only in `Ended` state, cannot override a dispute.

### ✅ Phase 4: Legal Wrapper + DAO (Completed)

- [x] Deployed `LegalWrapper` on Sepolia — anchors IPFS lease hashes + jurisdiction.
- [x] Deployed `KlerosResolver` — bridges RentChain disputes to a Kleros-compatible arbitrator.
- [x] Fee pool funded; arbitrator rules on disputed deposits.
- [x] Escalation requires an anchored document — no anchoring, no arbitration.
- [x] 16 unit tests for `LegalWrapper`, 12 for `KlerosResolver`.

### ✅ Phase 5: DeFi Lending (Completed)

- [x] Deployed `RentChainLending` on Sepolia — accepts `PropertyNFT` as collateral.
- [x] Uses Circle's Sepolia USDC (`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`) as the loan asset.
- [x] 50% LTV; 75% liquidation threshold; 10% APR; 10% liquidation penalty.
- [x] `borrow`, `repay`, `withdrawCollateral`, `liquidate` all implemented.
- [x] 11 unit tests + Anvil E2E verified.

### ✅ Phase 6: ZK Privacy Layer — Circuits & Verification (Completed)

**Circuits (Noir + UltraHonk):**
- [x] Four circuits: `good_rental_history`, `income_sufficiency`, `kYC_proof`, `no_disputes`.
- [x] Compile, witness, and prove via `nargo` + `bb` (`--oracle_hash keccak`).
- [x] Unit tests in each circuit (passing).

**On-chain verification layer:**
- [x] Four Solidity verifiers generated with `bb write_solidity_verifier`.
- [x] `ZKAttestation` verifies proofs on-chain and records per-tenant attestations.
- [x] Replaced the earlier ECDSA trusted-signer model with cryptographic proof verification.
- [x] Sender binding via `publicInputs[0] == msg.sender`.
- [x] `RentalAgreement.signAsTenant()` gated on a valid `good_history` attestation.
- [x] 4 verifier tests + 4 E2E tests through `ZKAttestation` + gate integration test (all passing).

**⚠️ Sepolia deployment status: NOT DEPLOYED — EIP-170 code-size limit.**
See the *Known Limitations* section below. All Phase 6 functionality is verified locally and via Foundry tests; on-chain deployment on Ethereum Sepolia is blocked by the verifier contract size. This is a platform constraint, not a bug in the implementation.

## 📋 Deployed Contracts (Sepolia)

| Contract | Address | Notes |
|----------|---------|-------|
| **PropertyNFT** | [`0x9AF296DA87Be1251964ab209C46B35672DC4808E`](https://sepolia.etherscan.io/address/0x9AF296DA87Be1251964ab209C46B35672DC4808E) | ERC-721 property titles |
| **RentalHistory** | [`0xa4273A4CEAf340f986476462539e1d3B8276bc28`](https://sepolia.etherscan.io/address/0xa4273A4CEAf340f986476462539e1d3B8276bc28) | Immutable agreement records |
| **RentChainFactory** | [`0x37C90213DD1712eDaCE79294Fe2Ea09Cac5c9b6F`](https://sepolia.etherscan.io/address/0x37C90213DD1712eDaCE79294Fe2Ea09Cac5c9b6F) | Deploys RentalAgreement instances |
| **RentalAgreement (V2 example)** | [`0x26a1C334C57cAc0925723490Cb59586B391BD4D3`](https://sepolia.etherscan.io/address/0x26a1C334C57cAc0925723490Cb59586B391BD4D3) | Created via factory |
| **RentStreamToken** | [`0xab660b16BB9af8E75fEF5Fc0A40F99f22Dd6988a`](https://sepolia.etherscan.io/address/0xab660b16BB9af8E75fEF5Fc0A40F99f22Dd6988a) | Linked to V2 agreement |
| **RentalOracle** | [`0x598B526F0EB6de6b01A499e5B504964869CAbedA`](https://sepolia.etherscan.io/address/0x598B526F0EB6de6b01A499e5B504964869CAbedA) | Chainlink Functions inspection oracle |
| **LegalWrapper** | [`0x9798Bd262856aFDA145CDF30c23354597Aa84734`](https://sepolia.etherscan.io/address/0x9798Bd262856aFDA145CDF30c23354597Aa84734) | IPFS lease anchoring |
| **MockArbitrator** | [`0xde15d862E246CC8B289f00d589024774AAEcd580`](https://sepolia.etherscan.io/address/0xde15d862E246CC8B289f00d589024774AAEcd580) | Test arbitrator (Kleros on mainnet) |
| **KlerosResolver** | [`0x28F87cBA77485e4eD1A8962c2E5f8F52a97118cE`](https://sepolia.etherscan.io/address/0x28F87cBA77485e4eD1A8962c2E5f8F52a97118cE) | Dispute → arbitration adapter |
| **RentChainLending** | [`0x8B670193878DA75562C8A86AB938800A2e75cF17`](https://sepolia.etherscan.io/address/0x8B670193878DA75562C8A86AB938800A2e75cF17) | Collateralized lending pool |
| **USDC (Sepolia)** | [`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`](https://sepolia.etherscan.io/address/0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238) | Circle-issued test USDC |

### 🗄️ Legacy Deployments

| Contract | Address | Notes |
|----------|---------|-------|
| RentalHistory (legacy) | [`0x3c7F604022dAc5490BC2F2e1EF49641Ee16a0e16`](https://sepolia.etherscan.io/address/0x3c7F604022dAc5490BC2F2e1EF49641Ee16a0e16) | Original combined V1 deployment |
| RentalAgreement (manual, pre-factory) | [`0xD65C262902E61ed068Fb42e6461E150d264394Cc`](https://sepolia.etherscan.io/address/0xD65C262902E61ed068Fb42e6461E150d264394Cc) | Manual deploy, no factory, no oracle |


 
## 🚀 Deployment (Sepolia)

Deploy in this order:

### 1. RentalHistory

```bash
forge create src/RentalHistory.sol:RentalHistory \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast
# → $HISTORY_V2
```

### 2. RentChainFactory

```bash
forge create src/RentChainFactory.sol:RentChainFactory \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast \
    --constructor-args $HISTORY_V2
# → $FACTORY_V2
```

### 3.  PropertyNFT

```bash
forge create src/PropertyNFT.sol:PropertyNFT \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast
# → $NFT_V2
```
 
### 4. Mint a property

```bash
cast send $NFT_V2 "registerProperty(string)" "ipfs://..." \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 5. Create a RentalAgreement via the factory

```bash
cast send $FACTORY_V2 "createAgreement(address,uint256,uint256,uint256,uint256,address,uint256)" \
    $TENANT_ADDRESS 1ether 2ether 2592000 86400 $NFT_V2 1 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
# → $AGREEMENT_V2 (from AgreementCreated event)
```

###  6. RentStreamToken

```bash
forge create src/RentStreamToken.sol:RentStreamToken \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast \
    --constructor-args "RentChain Stream" "RCS" 12ether $AGREEMENT_V2 $OWNER_ADDRESS
# → $TOKEN_V2
```

###  7.Link the token to the agreement

```bash
cast send $AGREEMENT_V2 "setRentStreamToken(address)" $TOKEN_V2 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```    
### 8. RentalOracle

```bash
forge create src/RentalOracle.sol:RentalOracle \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast \
    --constructor-args \
        0xb83E47C2bC239B3bf370bc41e1459A34b41238D0 \
        0 \
        0x66756e2d657468657265756d2d7365706f6c69612d310000000000000000000000 \
        $OWNER_ADDRESS
# → $ORACLE_V2
```

### 9. Link oracle to agreement (optional, before signing)

```bash
cast send $AGREEMENT_V2 "setOracle(address)" $ORACLE_V2 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send $ORACLE_V2 "registerAgreement(address)" $AGREEMENT_V2 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 10. LegalWrapper

```bash
forge create src/LegalWrapper.sol:LegalWrapper \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast
# → $WRAPPER_V2
```

### 11. MockArbitrator (replace with Kleros on mainnet)

```bash
forge create test/mocks/MockArbitrator.sol:MockArbitrator \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast
# → $ARBITER_V2
```

### 12. KlerosResolver

```bash
forge create src/KlerosResolver.sol:KlerosResolver \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast \
    --constructor-args $ARBITER_V2 $WRAPPER_V2
# → $RESOLVER_V2
``` 

### 13. Fund the resolver's fee pool

```bash
cast send $RESOLVER_V2 "fundFeePool()" --value 0.05ether \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 14. Anchor the lease and wire the resolver (per agreement, pre-signing)

```bash
# Anchor the lease document
cast send $WRAPPER_V2 "anchorDocument(address,bytes32,string)" \
    $AGREEMENT_V2 $(cast keccak "lease-v1") "US-CA" \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Wire the resolver (must be in Created state)
cast send $AGREEMENT_V2 "setDisputeResolver(address)" $RESOLVER_V2 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 15. RentChainLending

```bash
forge create src/RentChainLending.sol:RentChainLending \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --broadcast \
    --constructor-args $NFT_V2 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
# → $LENDING_V2


# Approve USDC (get test USDC from https://faucet.circle.com/)
cast send 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 "approve(address,uint256)" $LENDING_V2 20000000 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send $LENDING_V2 "fundPool(uint256)" 20000000 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY

```

## ⚠️ Known Limitations

### ZK Verifiers exceed EIP-170 on Ethereum Sepolia

The four UltraHonk verifier contracts generated by `bb write_solidity_verifier` exceed Ethereum's **EIP-170 contract code-size limit of 24,576 bytes**.

- Each generated verifier compiles to roughly **33–35 KB** of deployed bytecode.
- Locally (`forge test`, `anvil`), this is not enforced, so all Phase 6 tests pass.
- On Ethereum Sepolia, deployment reverts with `CreateContractSizeLimit`.

**Why the verifier is large:** the generated contract contains the full UltraHonk verification algorithm — sumcheck, Shplemini, KZG, transcript hashing, and field arithmetic — plus the embedded verification key (`HonkVerificationKey.loadVerificationKey()`). All of this compiles into a single contract.

**What this means for Phase 6:**

| Layer | Status |
|-------|--------|
| Noir circuits | ✅ Complete |
| Off-chain proof generation | ✅ Complete |
| Solidity verifiers (compiled) | ✅ Complete |
| `ZKAttestation` + `RentalAgreement` gate | ✅ Complete |
| Verifier tests + E2E tests | ✅ Complete (local) |
| On-chain verification on Ethereum Sepolia | ❌ Blocked by EIP-170 |

**Workarounds considered:**

1. **Library split** — Move `ZKTranscriptLib` (the largest internal library) into a separately deployed contract and link at deploy time. This brings the main verifier under the 24 KB limit. Requires editing the `bb`-generated Solidity to change library function visibility from `internal` to `external`, which must be reapplied on every regeneration. Documented as a viable path; not implemented in this version.

2. **Deploy on an L2** — Base Sepolia, Arbitrum Sepolia, and Optimism Sepolia do not enforce EIP-170 at the sequencer. The same Solidity deploys without modification. Recommended for a live demo; not done here to keep all phases on the same network.

3. **Newer `bb` with `--optimized` flag** — Newer Aztec packages releases include an `--optimized` flag for `write_solidity_verifier` that generates a gas-optimized, assembly-based verifier. Not available in `bb 0.87.0` (the version compatible with `nargo 1.0.0-beta.12`). Upgrading would require regenerating all four circuits, VKs, and verifiers.

**Decision:** Phase 6 is complete as a *verification layer* — circuits, proofs, on-chain verifier contracts, `ZKAttestation`, and the `RentalAgreement` gate all work and are fully tested. The Sepolia deployment is deferred because the platform cannot host the generated verifier contracts within code-size limits. This is documented here for transparency rather than hidden.

## 🚀 Remaining Roadmap

| Feature | Implementation |
|---------|----------------|
| **ZK verifier deployment (EIP-170 workaround)** | Split `ZKTranscriptLib` into an external library so the verifier fits under 24 KB, then deploy the full ZK stack to Ethereum Sepolia. Alternatively, deploy on Base Sepolia or Arbitrum Sepolia. |
| **Browser-side proving** | Replace the `nargo`/`bb` CLI flow with `@noir-lang/noir_js` + `@aztec/bb.js` so tenants can generate proofs from a web app. |
| **Mina zkApp Implementation** | Parallel `o1js` implementation targeting Mina Builder Grants. |

## 🙏 Acknowledgements

- [Foundry](https://book.getfoundry.sh/) — Solidity development toolkit
- [OpenZeppelin](https://openzeppelin.com/contracts/) — secure contract primitives
- [Chainlink Functions](https://docs.chain.link/chainlink-functions) — off-chain data integration


## 🤝 Contributing

Issues and PRs welcome. For major changes, open an issue first to discuss.