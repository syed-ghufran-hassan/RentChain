// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDisputeResolver.sol";
import "./interfaces/IArbitrator.sol";
import "./interfaces/ILegalWrapper.sol";

interface IArbitrableAgreement {
    function resolveDispute(bool tenantWins) external;
    function owner() external view returns (address);
    function tenant() external view returns (address);
}

contract KlerosResolver is IDisputeResolver, Ownable {
    IArbitrator public arbitrator;
    ILegalWrapper public legalWrapper;

    // For creating a dispute, the resolver needs to pay the arbitration fee.
    // Anyone can top up this pool.
    uint256 public feePool;

    struct Case {
        address agreement;
        address owner;
        address tenant;
        uint256 arbitratorDisputeId;
        bool resolved;
    }

    mapping(address => Case) public cases; // agreement => case
    mapping(uint256 => address) public disputeToAgreement; // arbitrator disputeId => agreement
    mapping(uint256 => bool) public caseRuled; // arbitrator disputeId => resolved

    event CaseOpened(address indexed agreement, uint256 indexed arbitratorDisputeId);
    event CaseResolved(address indexed agreement, bool tenantWins);
    event FeePoolFunded(address indexed from, uint256 amount);
    event FeePoolWithdrawn(address indexed to, uint256 amount);

    modifier onlyArbitrator() {
        require(msg.sender == address(arbitrator), "Only arbitrator");
        _;
    }

    constructor(address _arbitrator, address _legalWrapper) Ownable(msg.sender) {
        require(_arbitrator != address(0), "Invalid arbitrator");
        require(_legalWrapper != address(0), "Invalid legal wrapper");
        arbitrator = IArbitrator(_arbitrator);
        legalWrapper = ILegalWrapper(_legalWrapper);
    }

    /// @notice Called by RentalAgreement when a dispute is raised.
    function escalate(address agreement) external override {
        require(cases[agreement].agreement == address(0), "Case already open");
        require(legalWrapper.isEscalated(agreement) == false, "Already escalated");

        uint256 cost = arbitrator.arbitrationCost();
        require(feePool >= cost, "Insufficient fee pool");

        // Encode evidence: the legal document hash from LegalWrapper
        bytes32 docHash = legalWrapper.getDocumentHash(agreement);
        string memory evidence = _toHexString(docHash);

        // Create Kleros dispute: 2 choices = [Owner wins, Tenant wins]
        uint256 disputeId = arbitrator.createDispute{value: cost}(2, evidence);
        feePool -= cost;

        address ownerAddr = IArbitrableAgreement(agreement).owner();
        address tenantAddr = IArbitrableAgreement(agreement).tenant();

        cases[agreement] = Case({
            agreement: agreement, owner: ownerAddr, tenant: tenantAddr, arbitratorDisputeId: disputeId, resolved: false
        });
        disputeToAgreement[disputeId] = agreement;

        // Record escalation in LegalWrapper
        legalWrapper.recordEscalation(agreement, disputeId);

        emit CaseOpened(agreement, disputeId);
    }

    /// @notice Called by the arbitrator when a ruling is made.
    /// @param disputeId  Arbitrator's dispute ID.
    /// @param ruling     0 = owner wins, 1 = tenant wins.
    function rule(uint256 disputeId, uint256 ruling) external onlyArbitrator {
        address agreement = disputeToAgreement[disputeId];
        require(agreement != address(0), "Unknown dispute");
        require(!caseRuled[disputeId], "Already ruled");

        caseRuled[disputeId] = true;
        bool tenantWins = (ruling == 1);

        // The agreement's resolveDispute requires msg.sender == disputeResolver,
        // which is this contract. So the call succeeds.
        IArbitrableAgreement(agreement).resolveDispute(tenantWins);

        cases[agreement].resolved = true;
        emit CaseResolved(agreement, tenantWins);
    }

    /// @notice Manual resolution by the owner — only as an emergency fallback.
    function resolve(address agreement, bool tenantWins) external override onlyOwner {
        IArbitrableAgreement(agreement).resolveDispute(tenantWins);
        cases[agreement].resolved = true;
        emit CaseResolved(agreement, tenantWins);
    }

    // ---------- Fee Pool ----------

    function fundFeePool() external payable {
        require(msg.value > 0, "No funds");
        feePool += msg.value;
        emit FeePoolFunded(msg.sender, msg.value);
    }

    function withdrawFees(address to, uint256 amount) external onlyOwner {
        require(amount <= feePool, "Insufficient pool");
        feePool -= amount;
        (bool sent,) = to.call{value: amount}("");
        require(sent, "Transfer failed");
        emit FeePoolWithdrawn(to, amount);
    }

    // ---------- Admin ----------

    function setArbitrator(address _arbitrator) external onlyOwner {
        arbitrator = IArbitrator(_arbitrator);
    }

    function setLegalWrapper(address _wrapper) external onlyOwner {
        legalWrapper = ILegalWrapper(_wrapper);
    }

    // ---------- Helpers ----------

    function _toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    receive() external payable {
        feePool += msg.value;
        emit FeePoolFunded(msg.sender, msg.value);
    }
}
