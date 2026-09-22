// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";

contract ZKAttestation is Ownable {
    IVerifier public immutable goodHistoryVerifier;
    IVerifier public immutable incomeVerifier;
    IVerifier public immutable kycVerifier;
    IVerifier public immutable noDisputesVerifier;

    bytes32 public constant GOOD_HISTORY_PROOF = keccak256("good_history");
    bytes32 public constant INCOME_PROOF       = keccak256("income");
    bytes32 public constant KYC_PROOF          = keccak256("kyc");
    bytes32 public constant NO_DISPUTES_PROOF  = keccak256("no_disputes");

    struct Attestation {
        bytes32 proofType;
        bytes32 publicInputsHash;
        uint256 expiry;
        bool revoked;
    }

    mapping(address => Attestation[]) public attestations;

    event AttestationSubmitted(address indexed tenant, bytes32 proofType, uint256 expiry);
    event AttestationRevoked(address indexed tenant, uint256 index);

    constructor(
        address _goodHistoryVerifier,
        address _incomeVerifier,
        address _kycVerifier,
        address _noDisputesVerifier
    ) Ownable(msg.sender) {
        goodHistoryVerifier = IVerifier(_goodHistoryVerifier);
        incomeVerifier      = IVerifier(_incomeVerifier);
        kycVerifier         = IVerifier(_kycVerifier);
        noDisputesVerifier  = IVerifier(_noDisputesVerifier);
    }

    /// @notice Submit a ZK proof. Verified cryptographically on-chain.
    /// @param proofType   One of the four proof type constants.
    /// @param proof       The UltraHonk proof bytes from `bb prove`.
    /// @param publicInputs The public inputs from `bb prove`, in ABI order.
    /// @param expiry      Unix timestamp after which this attestation is invalid.
    function submitAttestation(
        bytes32 proofType,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        uint256 expiry
    ) external {
        require(block.timestamp < expiry, "Already expired");

        IVerifier verifier = _verifierFor(proofType);
        require(address(verifier) != address(0), "Unknown proof type");

        // Cryptographic verification. Reverts if the proof doesn't check out.
        require(verifier.verify(proof, publicInputs), "Invalid proof");

        // Every circuit now binds tenant_address as publicInputs[0].
        // This is what stops someone replaying another tenant's proof.
        require(
            uint256(publicInputs[0]) == uint256(uint160(msg.sender)),
            "Proof not bound to sender"
        );

        bytes32 inputsHash = keccak256(abi.encodePacked(publicInputs));

        attestations[msg.sender].push(Attestation({
            proofType: proofType,
            publicInputsHash: inputsHash,
            expiry: expiry,
            revoked: false
        }));

        emit AttestationSubmitted(msg.sender, proofType, expiry);
    }

    function isVerified(address tenant, bytes32 proofType) external view returns (bool) {
        Attestation[] storage list = attestations[tenant];
        for (uint256 i = 0; i < list.length; i++) {
            if (
                list[i].proofType == proofType &&
                !list[i].revoked &&
                list[i].expiry > block.timestamp
            ) {
                return true;
            }
        }
        return false;
    }

    function revoke(address tenant, uint256 index) external onlyOwner {
        attestations[tenant][index].revoked = true;
        emit AttestationRevoked(tenant, index);
    }

    function _verifierFor(bytes32 proofType) internal view returns (IVerifier) {
        if (proofType == GOOD_HISTORY_PROOF) return goodHistoryVerifier;
        if (proofType == INCOME_PROOF)       return incomeVerifier;
        if (proofType == KYC_PROOF)          return kycVerifier;
        if (proofType == NO_DISPUTES_PROOF)  return noDisputesVerifier;
        return IVerifier(address(0));
    }
}