// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RentalOracle.sol";
import "../src/RentalAgreement.sol";
import "../src/RentalHistory.sol";
import "../src/RentChainFactory.sol";
import "../src/PropertyNFT.sol";

/// @notice Mock Chainlink Functions client for testing.
contract MockFunctionsClient is IFunctionsClient {
    bytes32 public nextRequestId = keccak256("req");
    bytes public lastResponse;

    function sendRequest(string memory, bytes[] memory, uint64, uint32, bytes32) external override returns (bytes32) {
        return nextRequestId;
    }

    function setNextRequestId(bytes32 id) external {
        nextRequestId = id;
    }
}

contract RentalOracleTest is Test {
    RentalOracle public oracle;
    MockFunctionsClient public mockClient;
    PropertyNFT public nft;
    RentalHistory public history;
    RentChainFactory public factory;
    RentalAgreement public agreement;

    address public owner = address(0x1);
    address public tenant = address(0x2);

    uint256 public tokenId;
    uint256 public constant RENT = 1 ether;
    uint256 public constant DEPOSIT = 2 ether;
    uint256 public constant DURATION = 30 days;
    uint256 public constant INTERVAL = 1 days;

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(tenant, 100 ether);

        // Mock Chainlink Functions client
        mockClient = new MockFunctionsClient();

        // Deploy oracle
        oracle = new RentalOracle(
            0xb83E47C2bC239B3bf370bc41e1459A34b41238D0, // Sepolia Functions Router
            1,
            bytes32(0),
            address(mockClient)
        );

        // Deploy core contracts
        nft = new PropertyNFT();
        vm.prank(owner);
        tokenId = nft.registerProperty("ipfs://QmTest");

        history = new RentalHistory();
        factory = new RentChainFactory(address(history));
        vm.prank(owner);
        agreement = RentalAgreement(
            payable(factory.createAgreement(tenant, RENT, DEPOSIT, DURATION, INTERVAL, address(nft), tokenId))
        );
    }

    // ------------------------------------------------------------------------
    // 1. Oracle registration
    // ------------------------------------------------------------------------
    function test_RegisterAgreement() public {
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));
        assertEq(oracle.registeredBy(address(agreement)), owner);
    }

    function test_NonOwnerCannotRegister() public {
        vm.prank(tenant);
        vm.expectRevert("Only agreement owner can register");
        oracle.registerAgreement(address(agreement));
    }

    function test_CannotRegisterTwice() public {
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));
        vm.prank(owner);
        vm.expectRevert("Already registered");
        oracle.registerAgreement(address(agreement));
    }

    function test_UnregisterAgreement() public {
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));
        vm.prank(owner);
        oracle.unregisterAgreement(address(agreement));
        assertEq(oracle.registeredBy(address(agreement)), address(0));
    }

    // ------------------------------------------------------------------------
    // 2. Owner links oracle to agreement (must be pre-signing)
    // ------------------------------------------------------------------------
    function test_SetOracleBeforeSigning() public {
        vm.prank(owner);
        agreement.setOracle(address(oracle));
        assertEq(agreement.oracle(), address(oracle));
    }

    function test_CannotSetOracleAfterSigning() public {
        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(owner);
        vm.expectRevert("Oracle frozen after signing");
        agreement.setOracle(address(oracle));
    }

    // ------------------------------------------------------------------------
    // 3. Oracle releases deposit on successful inspection
    // ------------------------------------------------------------------------
    function test_OracleReleasesDepositOnPass() public {
        // Setup
        vm.prank(owner);
        agreement.setOracle(address(oracle));
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Owner requests inspection
        vm.prank(owner);
        bytes32 reqId = oracle.requestInspection(address(agreement), "https://api.example.com");

        // Simulate Chainlink callback with passed = 1
        bytes memory response = abi.encode(uint256(1));
        vm.prank(address(mockClient)); // pretend caller is fine — real impl checks router
        oracle.handleInspectionResult(reqId, response);

        assertTrue(agreement.depositReleased());
        assertEq(agreement.depositHeld(), 0);
    }

    // ------------------------------------------------------------------------
    // 4. Oracle does NOT release when inspection fails
    // ------------------------------------------------------------------------
    function test_OracleDoesNotReleaseOnFail() public {
        vm.prank(owner);
        agreement.setOracle(address(oracle));
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(owner);
        bytes32 reqId = oracle.requestInspection(address(agreement), "https://api.example.com");

        bytes memory response = abi.encode(uint256(0));
        oracle.handleInspectionResult(reqId, response);

        assertFalse(agreement.depositReleased());
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    // ------------------------------------------------------------------------
    // 5. Oracle cannot override a dispute
    // ------------------------------------------------------------------------
    function test_OracleCannotOverrideDispute() public {
        vm.prank(owner);
        agreement.setOracle(address(oracle));
        vm.prank(owner);
        oracle.registerAgreement(address(agreement));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Tenant disputes
        vm.prank(tenant);
        agreement.disputeDeposit();
        assertEq(uint256(agreement.state()), uint256(RentalAgreement.State.Disputed));

        // Owner requests inspection — the callback must silently fail
        vm.prank(owner);
        bytes32 reqId = oracle.requestInspection(address(agreement), "https://api.example.com");

        bytes memory response = abi.encode(uint256(1));
        oracle.handleInspectionResult(reqId, response); // no revert

        // Deposit was NOT released because state was Disputed
        assertFalse(agreement.depositReleased());
        assertEq(agreement.depositHeld(), DEPOSIT);
    }

    // ------------------------------------------------------------------------
    // 6. Oracle cannot release after window has closed
    // ------------------------------------------------------------------------
    function test_OracleRevertsAfterWindowClosed() public {
        vm.prank(owner);
        agreement.setOracle(address(oracle));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        // Warp past the 7-day window
        vm.warp(block.timestamp + 8 days);

        // Direct oracle call should revert
        vm.prank(address(oracle));
        vm.expectRevert("Window closed");
        agreement.releaseDepositByOracle();
    }

    // ------------------------------------------------------------------------
    // 7. Only oracle can call releaseDepositByOracle
    // ------------------------------------------------------------------------
    function test_OnlyOracleCanRelease() public {
        vm.prank(owner);
        agreement.setOracle(address(oracle));

        vm.prank(owner);
        agreement.signAsOwner();
        vm.prank(tenant);
        agreement.signAsTenant{value: DEPOSIT}();

        vm.warp(block.timestamp + DURATION + 1 days);
        vm.prank(owner);
        agreement.endLease();

        vm.prank(tenant);
        vm.expectRevert("Only oracle");
        agreement.releaseDepositByOracle();
    }

    // ------------------------------------------------------------------------
    // 8. Unregistered agreements cannot request inspection
    // ------------------------------------------------------------------------
    function test_UnregisteredCannotRequestInspection() public {
        vm.prank(owner);
        vm.expectRevert("Not registered");
        oracle.requestInspection(address(agreement), "https://api.example.com");
    }
}
