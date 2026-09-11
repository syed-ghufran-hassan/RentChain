// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IRentalHistory.sol";

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
    mapping(address => AgreementRecord) public agreements;

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
