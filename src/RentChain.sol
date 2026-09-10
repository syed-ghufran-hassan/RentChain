// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ------------------------------------------------------------------------
// Interface for Rental History (immutable record storage)
// ------------------------------------------------------------------------
interface IRentalHistory {
    function recordAgreement(
        address agreement,
        address owner,
        address tenant,
        uint256 rent,
        uint256 deposit,
        uint256 duration
    ) external;

    function recordActivation(address agreement, uint256 startTime) external;

    function recordPayment(address agreement, uint256 amount, uint256 timestamp) external;

    function recordEnd(address agreement, bool success) external;

    function recordDispute(address agreement) external;

    // View functions for frontend
    function getAgreementCount(address user) external view returns (uint256);

    function getAgreementAt(address user, uint256 index) external view returns (address);
}

// ------------------------------------------------------------------------
// Interface for PropertyNFT
// ------------------------------------------------------------------------

interface IPropertyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getTokensByOwner(address owner) external view returns (uint256[] memory);
}

interface IDisputeResolver {
    function escalate(address agreement) external;
    function resolve(address agreement, bool tenantWins) external;
}

// ------------------------------------------------------------------------
// Interface for RentStreamToken
// ------------------------------------------------------------------------


interface IRentStreamToken {
    function distributeRent() external payable;
}

// ------------------------------------------------------------------------
// RentalHistory – stores all agreements and events per user
// ------------------------------------------------------------------------
contract RentalHistory is IRentalHistory {
    struct AgreementRecord {
        address agreement;
        address owner;
        address tenant;
        uint256 rent;
        uint256 deposit;
        uint256 duration;
        uint256 startTime;
        uint256 endTime;
        bool ended;
        bool disputed;
        uint256 paymentCount;
        uint256 totalPaid;
    }

    mapping(address => address[]) public userAgreements;
    mapping(address => AgreementRecord) public agreements; // by agreement address

    function recordAgreement(
        address agreement,
        address owner,
        address tenant,
        uint256 rent,
        uint256 deposit,
        uint256 duration
    ) external override {
        require(agreements[agreement].agreement == address(0), "Already recorded");
        agreements[agreement] = AgreementRecord({
            agreement: agreement,
            owner: owner,
            tenant: tenant,
            rent: rent,
            deposit: deposit,
            duration: duration,
            startTime: 0,
            endTime: 0,
            ended: false,
            disputed: false,
            paymentCount: 0,
            totalPaid: 0
        });
        userAgreements[owner].push(agreement);
        userAgreements[tenant].push(agreement);
    }

    function recordActivation(address agreement, uint256 startTime) external override {
        AgreementRecord storage rec = agreements[agreement];
        require(rec.agreement != address(0), "Agreement not found");
        rec.startTime = startTime;
    }

    function recordPayment(address agreement, uint256 amount, uint256 timestamp) external override {
        AgreementRecord storage rec = agreements[agreement];
        require(rec.agreement != address(0), "Agreement not found");
        rec.paymentCount++;
        rec.totalPaid += amount;
    }

    function recordEnd(address agreement, bool success) external override {
        AgreementRecord storage rec = agreements[agreement];
        require(rec.agreement != address(0), "Agreement not found");
        rec.ended = true;
        rec.endTime = block.timestamp;
        // success flag can be stored if needed
    }

    function recordDispute(address agreement) external override {
        AgreementRecord storage rec = agreements[agreement];
        require(rec.agreement != address(0), "Agreement not found");
        rec.disputed = true;
    }

    function getAgreementCount(address user) external view override returns (uint256) {
        return userAgreements[user].length;
    }

    function getAgreementAt(address user, uint256 index) external view override returns (address) {
        return userAgreements[user][index];
    }
}

// ------------------------------------------------------------------------
// RentalAgreement – handles a single rental between owner and tenant
// ------------------------------------------------------------------------
contract RentalAgreement is ReentrancyGuard {
    enum State {
        Created,
        OwnerSigned,
        TenantSigned,
        Active,
        Ended,
        Disputed
    }

    address public owner;
    address public tenant;
    address public rentStreamToken;
    uint256 public rentAmount;
    uint256 public depositAmount;
    uint256 public leaseDuration;
    uint256 public paymentInterval;
    uint256 public leaseStart;
    uint256 public leaseEnd;
    uint256 public lastPaymentTimestamp;
    uint256 public rentHeld;
    uint256 public depositHeld;
    bool public depositReleased;
    State public state;
    IRentalHistory public history;

    // ---------- NFT Integration (V2) ----------
    uint256 public propertyNFTId;
    IPropertyNFT public propertyNFT;

    // ---------- Time‑lock dispute (V1 enhancement) ----------
    uint256 public constant DISPUTE_WINDOW = 7 days;
    uint256 public depositReleaseDeadline;
    bool public defaultOutcome; // true = tenant gets deposit on auto-release
    address public disputeResolver;

    // ---------- Events ----------
    event AgreementSigned(address indexed signer, State newState);
    event RentPaid(address indexed tenant, uint256 amount, uint256 timestamp);
    event RentWithdrawn(address indexed owner, uint256 amount);
    event LeaseEnded(address indexed owner, uint256 endTime);
    event DepositReleased(address indexed recipient, uint256 amount);
    event DisputeRaised(address indexed initiator);
    event DisputeResolved(address indexed resolver, bool tenantWins);

    // ---------- Modifiers ----------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    modifier onlyTenant() {
        require(msg.sender == tenant, "Not tenant");
        _;
    }
    modifier inState(State _state) {
        require(state == _state, "Invalid state");
        _;
    }
    modifier onlyResolver() {
        require(msg.sender == disputeResolver, "Only resolver");
        _;
    }
    modifier onlyNFTOwner() {
        require(
            address(propertyNFT) == address(0) || propertyNFT.ownerOf(propertyNFTId) == owner, "NFT not owned by owner"
        );
        _;
    }

    // ---------- Constructor ----------
    constructor(
        address _history,
        address _owner,
        address _tenant,
        uint256 _rentAmount,
        uint256 _depositAmount,
        uint256 _leaseDuration,
        uint256 _paymentInterval,
        address _propertyNFTAddress,
        uint256 _propertyNFTId
    ) {
        require(_owner != address(0) && _tenant != address(0) && _owner != _tenant, "Invalid addresses");
        require(_rentAmount > 0 && _depositAmount > 0 && _leaseDuration > 0 && _paymentInterval > 0, "Invalid terms");

        owner = _owner;
        tenant = _tenant;
        rentAmount = _rentAmount;
        depositAmount = _depositAmount;
        leaseDuration = _leaseDuration;
        paymentInterval = _paymentInterval;
        history = IRentalHistory(_history);

        if (_propertyNFTAddress != address(0)) {
            propertyNFT = IPropertyNFT(_propertyNFTAddress);
            propertyNFTId = _propertyNFTId;
            require(propertyNFT.ownerOf(_propertyNFTId) == _owner, "Not the NFT owner");
        }

        state = State.Created;
    }

    // ---------- Signing ----------
    function signAsOwner() external onlyOwner {
        require(state == State.Created || state == State.TenantSigned, "Cannot sign now");
        if (state == State.Created) {
            state = State.OwnerSigned;
        } else if (state == State.TenantSigned) {
            _activate();
        }
        emit AgreementSigned(owner, state);
    }

    function signAsTenant() external payable onlyTenant {
        require(state == State.Created || state == State.OwnerSigned, "Cannot sign now");
        require(msg.value == depositAmount, "Must send exact deposit amount");
        depositHeld += msg.value;

        if (state == State.Created) {
            state = State.TenantSigned;
        } else if (state == State.OwnerSigned) {
            _activate();
        }
        emit AgreementSigned(tenant, state);
    }

    function _activate() internal {
        state = State.Active;
        leaseStart = block.timestamp;
        leaseEnd = block.timestamp + leaseDuration;
        lastPaymentTimestamp = block.timestamp;
        history.recordActivation(address(this), leaseStart);
    }

    // ---------- Rent Payment ----------
 function payRent() external payable onlyTenant inState(State.Active) nonReentrant {
    require(msg.value == rentAmount, "Must send exact rent amount");
    require(block.timestamp >= lastPaymentTimestamp + paymentInterval, "Payment not due yet");
    require(block.timestamp < leaseEnd, "Lease already ended");

    if (rentStreamToken != address(0)) {
        // Forward to token holders
        IRentStreamToken(rentStreamToken).distributeRent{value: msg.value}();
    } else {
        // Original path: accumulate for owner to withdraw
        rentHeld += msg.value;
    }

    lastPaymentTimestamp = block.timestamp;
    history.recordPayment(address(this), msg.value, block.timestamp);
    emit RentPaid(tenant, msg.value, block.timestamp);
}

    // ---------- Owner Rent Withdrawal ----------
  function withdrawRent() external onlyOwner onlyNFTOwner inState(State.Active) nonReentrant {
    require(rentStreamToken == address(0), "Rent is tokenized");
    uint256 amount = rentHeld;
    require(amount > 0, "No rent to withdraw");
    rentHeld = 0;
    (bool sent, ) = owner.call{value: amount}("");
    require(sent, "Failed to send rent");
    emit RentWithdrawn(owner, amount);
}

    // ---------- Lease End ----------
    function endLease() external onlyOwner inState(State.Active) {
        require(block.timestamp >= leaseEnd, "Lease not ended yet");
        state = State.Ended;
        // Set the auto-release deadline and default outcome (tenant gets deposit)
        depositReleaseDeadline = block.timestamp + DISPUTE_WINDOW;
        defaultOutcome = true;
        history.recordEnd(address(this), true);
        emit LeaseEnded(owner, block.timestamp);
    }

    // ---------- Auto‑release deposit (no dispute) ----------
    function autoReleaseDeposit() external {
        require(!depositReleased, "No deposit held"); //   check this first
        require(state != State.Disputed, "Disputed, cannot auto-release");
        require(state == State.Ended, "Invalid state");
        require(block.timestamp >= depositReleaseDeadline, "Deadline not reached");

        uint256 amount = depositHeld;
        require(amount > 0, "No deposit held");

        depositHeld = 0;
        depositReleased = true;

        address recipient = defaultOutcome ? tenant : owner;
        (bool sent,) = recipient.call{value: amount}("");
        require(sent, "Failed to send deposit");
        emit DepositReleased(recipient, amount);
    }

    // ---------- Deposit Release by Owner (legacy fallback) ----------
    function releaseDeposit() external onlyOwner nonReentrant {
        require(!depositReleased, "Deposit already released"); //  check this first
        require(state != State.Disputed, "Disputed, use resolver or auto-release");
        require(state == State.Ended, "Invalid state");

        uint256 amount = depositHeld;
        require(amount > 0, "No deposit held");

        depositHeld = 0;
        depositReleased = true;

        (bool sent,) = tenant.call{value: amount}("");
        require(sent, "Failed to send deposit");
        emit DepositReleased(tenant, amount);
    }

    // ---------- Dispute ----------
    function disputeDeposit() external inState(State.Ended) {
        require(msg.sender == owner || msg.sender == tenant, "Not party");
        require(block.timestamp < depositReleaseDeadline, "Dispute window closed");
        state = State.Disputed;
        depositReleaseDeadline = type(uint256).max; // pause auto-release
        history.recordDispute(address(this));

        if (disputeResolver != address(0)) {
            IDisputeResolver(disputeResolver).escalate(address(this));
        }
        emit DisputeRaised(msg.sender);
    }

    // ---------- Resolver (DAO) resolution ----------
    function resolveDispute(bool tenantWins) external onlyResolver {
        require(state == State.Disputed, "Not in dispute");
        uint256 amount = depositHeld;
        require(amount > 0, "No deposit");
        depositHeld = 0;
        depositReleased = true;

        address recipient = tenantWins ? tenant : owner;
        (bool sent,) = recipient.call{value: amount}("");
        require(sent, "Transfer failed");
        emit DepositReleased(recipient, amount);
        emit DisputeResolved(msg.sender, tenantWins);
        // Optionally reset state or keep as Disputed
    }

    // ---------- Admin ----------
    function setDisputeResolver(address _resolver) external onlyOwner {
        disputeResolver = _resolver;
    }

    // ---------- Reject direct ETH ----------
    receive() external payable {
        revert("Direct payments not allowed");
    }

    // ---------- View ----------
    function getStatus() external view returns (State) {
        return state;
    }

    // ---------- Set RentStreamToken  ---------- 
    function setRentStreamToken(address _token) external onlyOwner {
    require(_token != address(0), "Invalid token");
    require(
        state == State.Created || state == State.OwnerSigned || state == State.TenantSigned,
        "Too late to set"
    );
    rentStreamToken = _token;
}
}

// ------------------------------------------------------------------------
// RentChainFactory – deploys agreements and registers them in history
// ------------------------------------------------------------------------
contract RentChainFactory {
    address public history;

    event AgreementCreated(address indexed agreement, address indexed owner, address indexed tenant);

    constructor(address _history) {
        require(_history != address(0), "Invalid history address");
        history = _history;
    }

    function createAgreement(
        address tenant,
        uint256 rentAmount,
        uint256 depositAmount,
        uint256 leaseDuration,
        uint256 paymentInterval,
        address propertyNFTAddress,
        uint256 propertyNFTId
    ) external returns (address) {
        require(tenant != address(0) && tenant != msg.sender, "Invalid tenant");

        // Verify NFT ownership by the caller
        IPropertyNFT nft = IPropertyNFT(propertyNFTAddress);
        require(nft.ownerOf(propertyNFTId) == msg.sender, "Not the NFT owner");

        RentalAgreement agreement = new RentalAgreement(
            history,
            msg.sender,
            tenant,
            rentAmount,
            depositAmount,
            leaseDuration,
            paymentInterval,
            propertyNFTAddress,
            propertyNFTId
        );

        // Record agreement in history
        IRentalHistory(history)
            .recordAgreement(address(agreement), msg.sender, tenant, rentAmount, depositAmount, leaseDuration);

        emit AgreementCreated(address(agreement), msg.sender, tenant);
        return address(agreement);
    }
}
