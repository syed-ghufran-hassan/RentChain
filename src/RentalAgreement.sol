// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IRentalHistory.sol";
import "./interfaces/IPropertyNFT.sol";
import "./interfaces/IDisputeResolver.sol";
import "./interfaces/IRentStreamToken.sol";

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

    uint256 public propertyNFTId;
    IPropertyNFT public propertyNFT;

    uint256 public constant DISPUTE_WINDOW = 7 days;
    uint256 public depositReleaseDeadline;
    bool public defaultOutcome;
    address public disputeResolver;

    uint256 public constant DISPUTE_TIMEOUT = 30 days;
    uint256 public disputeFinalizeDeadline;

    event AgreementSigned(address indexed signer, State newState);
    event RentPaid(address indexed tenant, uint256 amount, uint256 timestamp);
    event RentWithdrawn(address indexed owner, uint256 amount);
    event LeaseEnded(address indexed owner, uint256 endTime);
    event DepositReleased(address indexed recipient, uint256 amount);
    event DisputeRaised(address indexed initiator);
    event DisputeResolved(address indexed resolver, bool tenantWins);
    event ResolverSet(address indexed resolver);
    event DisputeFinalized(address indexed caller, bool tenantWins);

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

    // ---------- Rent ----------
    function payRent() external payable onlyTenant inState(State.Active) nonReentrant {
        require(msg.value == rentAmount, "Must send exact rent amount");
        require(block.timestamp >= lastPaymentTimestamp + paymentInterval, "Payment not due yet");
        require(block.timestamp < leaseEnd, "Lease already ended");

        if (rentStreamToken != address(0)) {
            IRentStreamToken(rentStreamToken).distributeRent{value: msg.value}();
        } else {
            rentHeld += msg.value;
        }

        lastPaymentTimestamp = block.timestamp;
        history.recordPayment(address(this), msg.value, block.timestamp);
        emit RentPaid(tenant, msg.value, block.timestamp);
    }

    function withdrawRent() external onlyOwner onlyNFTOwner inState(State.Active) nonReentrant {
        require(rentStreamToken == address(0), "Rent is tokenized");
        uint256 amount = rentHeld;
        require(amount > 0, "No rent to withdraw");
        rentHeld = 0;
        (bool sent,) = owner.call{value: amount}("");
        require(sent, "Failed to send rent");
        emit RentWithdrawn(owner, amount);
    }

    // ---------- End Lease ----------
    function endLease() external onlyOwner inState(State.Active) {
        require(block.timestamp >= leaseEnd, "Lease not ended yet");
        state = State.Ended;
        depositReleaseDeadline = block.timestamp + DISPUTE_WINDOW;
        defaultOutcome = true;
        history.recordEnd(address(this), true);
        emit LeaseEnded(owner, block.timestamp);
    }

    // ---------- Release ----------
    function autoReleaseDeposit() external {
        require(!depositReleased, "No deposit held");
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

    function releaseDeposit() external onlyOwner nonReentrant {
        require(!depositReleased, "Deposit already released");
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
        depositReleaseDeadline = type(uint256).max;
        disputeFinalizeDeadline = block.timestamp + DISPUTE_TIMEOUT;

        history.recordDispute(address(this));

        if (disputeResolver != address(0)) {
            IDisputeResolver(disputeResolver).escalate(address(this));
        }
        emit DisputeRaised(msg.sender);
    }

    function resolveDispute(bool tenantWins) external onlyResolver {
        require(state == State.Disputed, "Not in dispute");
        require(block.timestamp < disputeFinalizeDeadline, "Timeout passed, use finalizeDispute");

        uint256 amount = depositHeld;
        require(amount > 0, "No deposit");
        depositHeld = 0;
        depositReleased = true;

        address recipient = tenantWins ? tenant : owner;
        (bool sent,) = recipient.call{value: amount}("");
        require(sent, "Transfer failed");
        emit DepositReleased(recipient, amount);
        emit DisputeResolved(msg.sender, tenantWins);
    }

    function finalizeDispute() external {
        require(state == State.Disputed, "Not in dispute");
        require(block.timestamp >= disputeFinalizeDeadline, "Timeout not reached");
        require(!depositReleased, "Deposit already released");

        uint256 amount = depositHeld;
        require(amount > 0, "No deposit");

        depositHeld = 0;
        depositReleased = true;

        (bool sent,) = tenant.call{value: amount}("");
        require(sent, "Transfer failed");

        emit DisputeFinalized(msg.sender, true);
        emit DepositReleased(tenant, amount);
    }

    // ---------- Admin ----------
    function setDisputeResolver(address _resolver) external onlyOwner {
        require(state == State.Created, "Resolver frozen after signing");
        disputeResolver = _resolver;
        emit ResolverSet(_resolver);
    }

    function setRentStreamToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        require(state == State.Created || state == State.OwnerSigned || state == State.TenantSigned, "Too late to set");
        rentStreamToken = _token;
    }

    receive() external payable {
        revert("Direct payments not allowed");
    }

    function getStatus() external view returns (State) {
        return state;
    }
}
