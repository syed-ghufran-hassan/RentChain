// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILegalWrapper {
    function anchorDocument(address agreement, bytes32 documentHash, string calldata jurisdiction) external;
    function recordEscalation(address agreement, uint256 caseId) external;
    function getDocumentHash(address agreement) external view returns (bytes32);
    function isEscalated(address agreement) external view returns (bool);
}
