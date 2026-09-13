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

---

## 🏗️ Architecture

The system consists of six core contracts:

| Contract | Purpose |
|----------|---------|
| **PropertyNFT** | ERC‑721 that represents property titles or leasehold rights. Mints an NFT per property with metadata (IPFS/Arweave). |
| **RentalHistory** | Stores immutable records of all agreements, payments, and events per user. Implements the `IRentalHistory` interface. |
| **RentalAgreement** | Handles the full rental lifecycle: signing, escrow, rent payments, lease end, time‑locked deposit release, and disputes. Uses OpenZeppelin's `ReentrancyGuard`. |
| **RentChainFactory** | Deploys new `RentalAgreement` instances, verifies NFT ownership, and registers agreements in `RentalHistory`. |
| **RentStreamToken** | ERC‑20 that represents a share of a future rent stream. Uses a reward‑per‑token accumulator to distribute rent to holders proportionally. |
| **RentalOracle** | Chainlink Functions consumer. After lease end, queries an off-chain inspection API and calls `releaseDepositByOracle()` if the inspection passed. |

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
10. **Resolver settles** → the resolver calls `resolveDispute(bool tenantWins)` → deposit goes to the winner.
11. **Timeout fallback** → if the resolver is silent for 30 days after a dispute is raised, anyone can call `finalizeDispute()` and the deposit goes to the tenant by default.
> **Resolver & oracle freeze:** `setDisputeResolver()` and `setOracle()` can only be called while the agreement is in the `Created` state. Once either party signs, both are locked — this prevents late appointment of a resolver that could bias an ongoing dispute.

## 💰 Yield Tokenization

Owners can sell future rent cash flows as ERC‑20 tokens:

1. Owner deploys `RentStreamToken(name, symbol, totalFutureRent, agreementAddress, ownerAddress)`.
2. Owner calls `RentalAgreement.setRentStreamToken(tokenAddress)` **before both parties sign**.
3. Owner transfers tokens to investors.
4. Each `payRent()` call forwards rent directly to the token contract, which updates the reward accumulator.
5. Investors call `RentStreamToken.claimReward()` to withdraw their share.

```markdown
 **Note on rounding:** because Solidity integer division truncates, `rewardPerTokenStored` accrues tiny rounding dust (a few wei per payment). The dust stays in the token contract; it does not affect any individual holder materially.
```

**Distribution formula (O(1) per payment):**

```markdown
**Reward accumulator (updated on each rent payment):**

$$
\text{rewardPerTokenStored} \mathrel{+}= \frac{\text{rentPaid} \times 10^{18}}{\text{totalSupply}}
$$

**Holder's claimable amount (view function):**

$$
\text{earned}(\text{holder}) = \frac{\text{balanceOf}(\text{holder}) \times \bigl(\text{rewardPerTokenStored} - \text{userRewardPerTokenPaid}[\text{holder}]\bigr)}{10^{18}} + \text{rewards}[\text{holder}]
$$
```

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
$ forge test --match-contract RentalOracleTest -vv
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

### Phase 4: Legal Wrapper

- Deploy LegalWrapper.

- Add document hash storage and dispute escalation.

### Phase 5: DeFi Lending

- Deploy RentChainLending using PropertyNFT as collateral.

- Integrate with existing lending protocols if needed.

## 📋 Deployed Contracts (Sepolia)

| Contract | Address | Notes |
|----------|---------|-------|
| PropertyNFT | [`0x9AF296DA87Be1251964ab209C46B35672DC4808E`](https://sepolia.etherscan.io/address/0x9AF296DA87Be1251964ab209C46B35672DC4808E) | ERC-721 property titles |
| RentalHistory | [`0xa4273A4CEAf340f986476462539e1d3B8276bc28`](https://sepolia.etherscan.io/address/0xa4273A4CEAf340f986476462539e1d3B8276bc28) | Immutable agreement records |
| RentChainFactory | [`0x37C90213DD1712eDaCE79294Fe2Ea09Cac5c9b6F`](https://sepolia.etherscan.io/address/0x37C90213DD1712eDaCE79294Fe2Ea09Cac5c9b6F) | Deploys RentalAgreement instances |
| RentalAgreement (V2 example) | [`0x26a1C334C57cAc0925723490Cb59586B391BD4D3`](https://sepolia.etherscan.io/address/0x26a1C334C57cAc0925723490Cb59586B391BD4D3) | Created via factory |
| RentStreamToken | [`0xab660b16BB9af8E75fEF5Fc0A40F99f22Dd6988a`](https://sepolia.etherscan.io/address/0xab660b16BB9af8E75fEF5Fc0A40F99f22Dd6988a) | Linked to V2 agreement |
| **RentalOracle** | [`0x598B526F0EB6de6b01A499e5B504964869CAbedA`](https://sepolia.etherscan.io/address/0x598B526F0EB6de6b01A499e5B504964869CAbedA) | Chainlink Functions inspection oracle |

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

## 🚀 V2 Upgrade Plan – Full RWA + ZK Feature Set

| Feature | Implementation |
|---------|----------------|   
| **Legal Wrapper + DAO** | `LegalWrapper` – stores document hashes and escalates disputes to a legal DAO (e.g., Kleros). |
| **DeFi Lending Integration** | `RentChainLending` – allows property owners to use Property NFTs as collateral for loans. |
| **ZK Privacy Layer (Noir)** | Noir circuits for rental history, income, no disputes, KYC; off‑chain verification + signed attestations. |

## 🙏 Acknowledgements

- [Foundry](https://book.getfoundry.sh/) — Solidity development toolkit
- [OpenZeppelin](https://openzeppelin.com/contracts/) — secure contract primitives
- [Chainlink Functions](https://docs.chain.link/chainlink-functions) — off-chain data integration


## 🤝 Contributing

Issues and PRs welcome. For major changes, open an issue first to discuss.