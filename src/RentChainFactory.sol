// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RentalAgreement.sol";
import "./interfaces/IRentalHistory.sol";
import "./interfaces/IPropertyNFT.sol";

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

        IRentalHistory(history)
            .recordAgreement(address(agreement), msg.sender, tenant, rentAmount, depositAmount, leaseDuration);

        emit AgreementCreated(address(agreement), msg.sender, tenant);
        return address(agreement);
    }
}
