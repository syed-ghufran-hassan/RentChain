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
    uint256 public rentAmount;
    uint256 public depositAmount;
    uint256 public leaseDuration; // seconds
    uint256 public paymentInterval; // seconds
    uint256 public leaseStart;
    uint256 public leaseEnd;
    uint256 public lastPaymentTimestamp;
    uint256 public rentHeld;
    uint256 public depositHeld;
    bool public depositReleased;
    State public state;
    IRentalHistory public history;

    event AgreementSigned(address indexed signer, State newState);
    event RentPaid(address indexed tenant, uint256 amount, uint256 timestamp);
    event RentWithdrawn(address indexed owner, uint256 amount);
    event LeaseEnded(address indexed owner, uint256 endTime);
    event DepositReleased(address indexed tenant, uint256 amount);
    event DisputeRaised(address indexed initiator);

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

    constructor(
        address _history,
        address _owner,
        address _tenant,
        uint256 _rentAmount,
        uint256 _depositAmount,
        uint256 _leaseDuration,
        uint256 _paymentInterval
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
        state = State.Created;
    }

    // Owner signs the agreement (can be called before or after tenant)
    function signAsOwner() external onlyOwner {
        require(state == State.Created || state == State.TenantSigned, "Cannot sign now");
        if (state == State.Created) {
            state = State.OwnerSigned;
        } else if (state == State.TenantSigned) {
            _activate();
        }
        emit AgreementSigned(owner, state);
    }

    // Tenant signs and pays the deposit (exact amount required)
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

    // Internal activation when both parties have signed
    function _activate() internal {
        state = State.Active;
        leaseStart = block.timestamp;
        leaseEnd = block.timestamp + leaseDuration;
        lastPaymentTimestamp = block.timestamp; // first payment due after one interval
        history.recordActivation(address(this), leaseStart);
    }

    // Tenant pays monthly rent – only when at least one interval has passed
    function payRent() external payable onlyTenant inState(State.Active) nonReentrant {
        require(msg.value == rentAmount, "Must send exact rent amount");
        require(block.timestamp >= lastPaymentTimestamp + paymentInterval, "Payment not due yet");
        require(block.timestamp < leaseEnd, "Lease already ended");

        rentHeld += msg.value;
        lastPaymentTimestamp = block.timestamp;
        history.recordPayment(address(this), msg.value, block.timestamp);
        emit RentPaid(tenant, msg.value, block.timestamp);
    }

    // Owner withdraws accumulated rent payments
    function withdrawRent() external onlyOwner inState(State.Active) nonReentrant {
        uint256 amount = rentHeld;
        require(amount > 0, "No rent to withdraw");
        rentHeld = 0;
        (bool sent,) = owner.call{value: amount}("");
        require(sent, "Failed to send rent");
        emit RentWithdrawn(owner, amount);
    }

    // Owner ends the lease after the lease duration has passed
    function endLease() external onlyOwner inState(State.Active) {
        require(block.timestamp >= leaseEnd, "Lease not ended yet");
        state = State.Ended;
        history.recordEnd(address(this), true);
        emit LeaseEnded(owner, block.timestamp);
    }

    // Owner releases the deposit to tenant after the lease has ended
    function releaseDeposit() external onlyOwner inState(State.Ended) nonReentrant {
        require(!depositReleased, "Deposit already released");
        uint256 amount = depositHeld;
        require(amount > 0, "No deposit held");
        depositHeld = 0;
        depositReleased = true;
        (bool sent,) = tenant.call{value: amount}("");
        require(sent, "Failed to send deposit");
        emit DepositReleased(tenant, amount);
    }

    // Either party can raise a dispute (only after the lease has ended)
    function disputeDeposit() external inState(State.Ended) {
        require(msg.sender == owner || msg.sender == tenant, "Not party");
        state = State.Disputed;
        history.recordDispute(address(this));
        emit DisputeRaised(msg.sender);
    }

    // Reject direct ETH transfers
    receive() external payable {
        revert("Direct payments not allowed");
    }

    // View helpers
    function getStatus() external view returns (State) {
        return state;
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
        uint256 leaseDuration, // in seconds
        uint256 paymentInterval // in seconds
    ) external returns (address) {
        require(tenant != address(0) && tenant != msg.sender, "Invalid tenant");

        RentalAgreement agreement =
            new RentalAgreement(history, msg.sender, tenant, rentAmount, depositAmount, leaseDuration, paymentInterval);

        // Record the agreement in the history contract
        IRentalHistory(history)
            .recordAgreement(address(agreement), msg.sender, tenant, rentAmount, depositAmount, leaseDuration
        );

        emit AgreementCreated(address(agreement), msg.sender, tenant);
        return address(agreement);
    }
}
