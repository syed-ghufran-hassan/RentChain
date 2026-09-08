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

---

## 🏗️ Architecture

The system consists of three core contracts:

| Contract | Purpose |
|----------|---------|
| **RentalHistory** | Stores immutable records of all agreements, payments, and events per user. Implements the `IRentalHistory` interface. |
| **RentalAgreement** | Handles the rental lifecycle: signing, escrow, rent payments, lease ending, deposit release, and disputes. Uses OpenZeppelin's `ReentrancyGuard`. |
| **RentChainFactory** | Deploys new `RentalAgreement` instances and automatically registers them in `RentalHistory`. |

 

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Future Implementation Plan:

Below is the plan for future implementation in rentchain:

#### Property Tokenization – Mint an ERC‑721 (NFT) or ERC‑1155 for each property that represents the title or leasehold rights.

#### Yield Tokenization – Allow the owner to tokenize future rent streams (e.g., mint ERC‑20 tokens that give holders a share of the monthly rent).

#### Oracle Integration – Connect to a Chainlink oracle to automatically trigger deposit releases based on verified off‑chain inspection reports.

#### Legal Wrapper – Add a legal clause (via a legal DAO or off‑chain registered document hash) that makes the on‑chain action enforceable in court.

#### Lending/DeFi integration – Allow property owners to use the tokenized property as collateral for a DeFi loan—a classic RWA use case.

## Implementation Roadmap

### Phase 1: Property Tokenization

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

## 🚀 V2 Upgrade Plan – Full RWA + ZK Feature Set

| Feature | Implementation |
|---------|----------------|
| **Property Tokenization (ERC‑721)** | `PropertyNFT` – mint NFTs representing property titles or leasehold rights. |
| **Yield Tokenization (ERC‑20)** | `RentStreamToken` – tokenizes future rent streams; holders receive proportional rent shares. |
| **Oracle Integration (Chainlink)** | `RentalOracle` – uses Chainlink Functions/Automation to trigger deposit release based on inspection reports. |
| **Legal Wrapper + DAO** | `LegalWrapper` – stores document hashes and escalates disputes to a legal DAO (e.g., Kleros). |
| **DeFi Lending Integration** | `RentChainLending` – allows property owners to use Property NFTs as collateral for loans. |
| **ZK Privacy Layer (Noir)** | Noir circuits for rental history, income, no disputes, KYC; off‑chain verification + signed attestations. |
