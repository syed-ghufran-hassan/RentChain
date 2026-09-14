// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ILegalWrapper.sol";

contract LegalWrapper is ILegalWrapper {
    struct LegalDoc {
        bytes32 documentHash;       // IPFS CID (sha256 or keccak)
        string jurisdiction;        // e.g., "US-CA", "EU-DE", "SG"
        uint256 anchoredAt;
        bool escalated;
        uint256 arbitrationCaseId;
    }

    mapping(address => LegalDoc) public docs;
    mapping(address => address) public anchoredBy;

    event DocumentAnchored(address indexed agreement, bytes32 documentHash, string jurisdiction, address indexed by);
    event DisputeEscalated(address indexed agreement, uint256 caseId);

    modifier onlyAgreementParty(address agreement) {
        // Anyone can anchor, but once anchored it can only be updated by the original anchorer.
        require(
            anchoredBy[agreement] == address(0) || anchoredBy[agreement] == msg.sender,
            "Not authorized"
        );
        _;
    }

    function anchorDocument(
        address agreement,
        bytes32 documentHash,
        string calldata jurisdiction
    ) external override onlyAgreementParty(agreement) {
        require(agreement != address(0), "Invalid agreement");
        require(documentHash != bytes32(0), "Invalid hash");
        require(bytes(jurisdiction).length > 0, "Invalid jurisdiction");

        if (anchoredBy[agreement] == address(0)) {
            anchoredBy[agreement] = msg.sender;
        }

        docs[agreement] = LegalDoc({
            documentHash: documentHash,
            jurisdiction: jurisdiction,
            anchoredAt: block.timestamp,
            escalated: docs[agreement].escalated,
            arbitrationCaseId: docs[agreement].arbitrationCaseId
        });

        emit DocumentAnchored(agreement, documentHash, jurisdiction, msg.sender);
    }

    function recordEscalation(address agreement, uint256 caseId) external override {
        require(anchoredBy[agreement] != address(0), "Agreement not anchored");
        require(!docs[agreement].escalated, "Already escalated");

        docs[agreement].escalated = true;
        docs[agreement].arbitrationCaseId = caseId;

        emit DisputeEscalated(agreement, caseId);
    }

    function getDocumentHash(address agreement) external view override returns (bytes32) {
        return docs[agreement].documentHash;
    }

    function isEscalated(address agreement) external view override returns (bool) {
        return docs[agreement].escalated;
    }
}