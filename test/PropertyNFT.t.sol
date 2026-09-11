// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PropertyNFT.sol";
import "../src/RentalHistory.sol";
import "../src/RentalAgreement.sol";
import "../src/RentChainFactory.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

contract PropertyNFTTest is Test {
    PropertyNFT public nft;
    RentalHistory public history;
    RentChainFactory public factory;
    RentalAgreement public agreement;

    address public owner = address(0x1);
    address public tenant = address(0x2);
    address public thirdParty = address(0x3);
    address public nonOwner = address(0x4);

    uint256 public constant RENT = 1 ether;
    uint256 public constant DEPOSIT = 2 ether;
    uint256 public constant DURATION = 30 days;
    uint256 public constant INTERVAL = 1 days;

    uint256 public tokenId;
    string public constant METADATA_URI = "ipfs://QmTestProperty";

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(tenant, 100 ether);
        vm.deal(thirdParty, 100 ether);
        vm.deal(nonOwner, 100 ether);

        nft = new PropertyNFT();

        vm.prank(owner);
        tokenId = nft.registerProperty(METADATA_URI);

        history = new RentalHistory();
        factory = new RentChainFactory(address(history));
    }

    function test_RegisterProperty() public {
        assertEq(nft.ownerOf(tokenId), owner);
        assertEq(nft.tokenURI(tokenId), METADATA_URI);
        uint256[] memory tokens = nft.getTokensByOwner(owner);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenId);
    }

    function test_CreateAgreementWithNFT() public {
        vm.prank(owner);
        address agreementAddr =
            factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
        agreement = RentalAgreement(payable(agreementAddr));

        assertEq(agreement.propertyNFTId(), tokenId);
        assertEq(address(agreement.propertyNFT()), address(nft));
        assertEq(agreement.owner(), owner);
        assertEq(agreement.tenant(), tenant);
    }

    function test_OnlyNFTOwnerCanCreate() public {
        vm.prank(nonOwner);
        vm.expectRevert("Not the NFT owner");
        factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
    }

    function test_ThirdPartyCannotCreate() public {
        vm.prank(thirdParty);
        vm.expectRevert("Not the NFT owner");
        factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
    }

    function test_NFTTransferBreaksAgreement() public {
        vm.prank(owner);
        address agreementAddr =
            factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId);
        agreement = RentalAgreement(payable(agreementAddr));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + 2 days);
        vm.prank(tenant);
        agreement.payRent{value: RENT}();

        vm.prank(owner);
        nft.transferFrom(owner, thirdParty, tokenId);

        vm.prank(owner);
        vm.expectRevert("NFT not owned by owner");
        agreement.withdrawRent();

        vm.prank(thirdParty);
        nft.transferFrom(thirdParty, owner, tokenId);

        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        agreement.withdrawRent();
        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter - ownerBalanceBefore, RENT);
    }

    function test_GetTokensByOwner() public {
        vm.prank(owner);
        uint256 tokenId2 = nft.registerProperty("ipfs://QmSecond");

        uint256[] memory tokens = nft.getTokensByOwner(owner);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], tokenId);
        assertEq(tokens[1], tokenId2);

        uint256[] memory tenantTokens = nft.getTokensByOwner(tenant);
        assertEq(tenantTokens.length, 0);
    }

    function test_TransferUpdatesOwnerLists() public {
        vm.prank(owner);
        nft.transferFrom(owner, tenant, tokenId);

        uint256[] memory ownerTokens = nft.getTokensByOwner(owner);
        assertEq(ownerTokens.length, 0);

        uint256[] memory tenantTokens = nft.getTokensByOwner(tenant);
        assertEq(tenantTokens.length, 1);
        assertEq(tenantTokens[0], tokenId);

        assertEq(nft.ownerOf(tokenId), tenant);
    }

    // ✅ Fixed: expect the correct revert message from OpenZeppelin
    function test_InvalidNFTIdReverts() public {
        uint256 invalidTokenId = 999;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ERC721NonexistentToken(uint256)")), invalidTokenId));
        factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), invalidTokenId);
    }

    function test_SupportsInterface() public {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId));
    }
}
