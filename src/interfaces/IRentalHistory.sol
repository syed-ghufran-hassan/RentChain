// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    function getAgreementCount(address user) external view returns (uint256);
    function getAgreementAt(address user, uint256 index) external view returns (address);
}
