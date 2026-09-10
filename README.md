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

---

## 🏗️ Architecture

The system consists of four core contracts:

| Contract | Purpose |
|----------|---------|
| **PropertyNFT** | ERC‑721 that represents property titles or leasehold rights. Mints an NFT per property with metadata (IPFS/Arweave). |
| **RentalHistory** | Stores immutable records of all agreements, payments, and events per user. Implements the `IRentalHistory` interface. |
| **RentalAgreement** | Handles the full rental lifecycle: signing, escrow, rent payments, lease end, time‑locked deposit release, and disputes. Uses OpenZeppelin's `ReentrancyGuard`. |
| **RentChainFactory** | Deploys new `RentalAgreement` instances, verifies NFT ownership, and registers agreements in `RentalHistory`. |

## 🔄 Rental Lifecycle

1. **Owner registers property** → mints a `PropertyNFT` via `registerProperty(metadataURI)`.
2. **Owner creates agreement** → calls `RentChainFactory.createAgreement(...)` passing the NFT address and token ID. The factory verifies NFT ownership and deploys a new `RentalAgreement`.
3. **Both parties sign** → `signAsOwner()` and `signAsTenant()` (deposit sent in ETH). Lease becomes `Active`.
4. **Tenant pays rent** → `payRent()` each `paymentInterval`.
5. **Owner withdraws rent** → `withdrawRent()` anytime while active.
6. **Lease ends** → owner calls `endLease()`. This starts a **7‑day dispute window**.
7. **Happy path** → if no dispute, anyone calls `autoReleaseDeposit()` after the window → deposit goes to tenant.
8. **Dispute path** → either party calls `disputeDeposit()` during the window. The auto‑release timer is paused and the `disputeResolver` (if set) is notified.
9. **Resolver settles** → the resolver calls `resolveDispute(bool tenantWins)` → deposit goes to the winner.

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

## Future Implementation Plan:

Below is the plan for future implementation in rentchain:

#### ✅ Phase 1: Property Tokenization (Completed)

- [x] Deployed `PropertyNFT` on Sepolia.
- [x] Integrated with `RentChainFactory` (verifies NFT ownership).
- [x] Updated `RentalAgreement` to reference NFT ID via `propertyNFTId`.
- [x] Added time-locked escrow + optional dispute resolver.

#### Yield Tokenization – Allow the owner to tokenize future rent streams (e.g., mint ERC‑20 tokens that give holders a share of the monthly rent).

#### Oracle Integration – Connect to a Chainlink oracle to automatically trigger deposit releases based on verified off‑chain inspection reports.

#### Legal Wrapper – Add a legal clause (via a legal DAO or off‑chain registered document hash) that makes the on‑chain action enforceable in court.

#### Lending/DeFi integration – Allow property owners to use the tokenized property as collateral for a DeFi loan—a classic RWA use case.

## Implementation Roadmap

### Phase 1: Property Tokenization (Completed)

- Deploying PropertyNFT and integrating with RentChainFactory.

- Updating RentalAgreement to reference NFT ID.

### Phase 2: Yield Tokenization

- Deploy RentStreamToken.

- Modify RentalAgreement to call distributeRent on each payment.

### Phase 3: Oracle Integration

- Set up Chainlink Functions or Use Chainlink Automation.

- Add oracle address to RentalAgreement and allow automated deposit release.

### Phase 4: Legal Wrapper

- Deploy LegalWrapper.

- Add document hash storage and dispute escalation.

### Phase 5: DeFi Lending

- Deploy RentChainLending using PropertyNFT as collateral.

- Integrate with existing lending protocols if needed.

## 📋 Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| RentalHistory | [`0x3c7F604022dAc5490BC2F2e1EF49641Ee16a0e16`](https://sepolia.etherscan.io/address/0x3c7F604022dAc5490BC2F2e1EF49641Ee16a0e16) |
| PropertyNFT | [`0x9AF296DA87Be1251964ab209C46B35672DC4808E`](https://sepolia.etherscan.io/address/0x9AF296DA87Be1251964ab209C46B35672DC4808E) |


 
### Deployment Command

```bash
$ forge create src/PropertyNFT.sol:PropertyNFT \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🚀 V2 Upgrade Plan – Full RWA + ZK Feature Set

| Feature | Implementation |
|---------|----------------| 
| **Yield Tokenization (ERC‑20)** | `RentStreamToken` – tokenizes future rent streams; holders receive proportional rent shares. |
| **Oracle Integration (Chainlink)** | `RentalOracle` – uses Chainlink Functions/Automation to trigger deposit release based on inspection reports. |
| **Legal Wrapper + DAO** | `LegalWrapper` – stores document hashes and escalates disputes to a legal DAO (e.g., Kleros). |
| **DeFi Lending Integration** | `RentChainLending` – allows property owners to use Property NFTs as collateral for loans. |
| **ZK Privacy Layer (Noir)** | Noir circuits for rental history, income, no disputes, KYC; off‑chain verification + signed attestations. |
