// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

// ------------------------------------------------------------------------
// Interfaces
// ------------------------------------------------------------------------
interface IOracleConsumer {
    function releaseDepositByOracle() external;
    function owner() external view returns (address);
}

interface IFunctionsClient {
    function sendRequest(
        string memory source,
        bytes[] memory args,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donID
    ) external returns (bytes32);
}

// ------------------------------------------------------------------------
// RentalOracle — Chainlink Functions consumer
// ------------------------------------------------------------------------
contract RentalOracle is Ownable {
    // Chainlink Functions config
    address public functionsRouter;
    uint64 public subscriptionId;
    bytes32 public donID;
    IFunctionsClient public functionsClient;

    // Chainlink Functions source code
    string public source = "const apiUrl = args[0];" "const agreement = args[1];"
        "const req = await Functions.makeHttpRequest({ url: apiUrl + '/inspection/' + agreement });"
        "if (req.error) { throw Error('HTTP error'); }" "const passed = req.data.passed === true;"
        "return Functions.encodeUint256(passed ? 1 : 0);";

    uint32 public constant GAS_LIMIT = 300_000;

    // agreement => owner who registered it
    mapping(address => address) public registeredBy;
    // requestId => agreement
    mapping(bytes32 => address) public pendingRequests;

    event AgreementRegistered(address indexed agreement, address indexed owner);
    event AgreementUnregistered(address indexed agreement);
    event InspectionRequested(address indexed agreement, bytes32 indexed requestId);
    event InspectionResult(address indexed agreement, bool passed, bool released);

    modifier onlyRegisteredOwner(address agreement) {
        require(registeredBy[agreement] == msg.sender, "Not the agreement owner");
        _;
    }

    constructor(address _functionsRouter, uint64 _subscriptionId, bytes32 _donID, address _functionsClient)
        Ownable(msg.sender)
    {
        require(_functionsRouter != address(0), "Invalid router");
        require(_functionsClient != address(0), "Invalid client");
        functionsRouter = _functionsRouter;
        subscriptionId = _subscriptionId;
        donID = _donID;
        functionsClient = IFunctionsClient(_functionsClient);
    }

    /// @notice Register an agreement to opt-in to oracle-based release.
    function registerAgreement(address agreement) external {
        require(agreement != address(0), "Invalid agreement");
        require(registeredBy[agreement] == address(0), "Already registered");
        require(IOracleConsumer(agreement).owner() == msg.sender, "Only agreement owner can register");
        registeredBy[agreement] = msg.sender;
        emit AgreementRegistered(agreement, msg.sender);
    }

    /// @notice Unregister an agreement (owner can opt out any time).
    function unregisterAgreement(address agreement) external onlyRegisteredOwner(agreement) {
        delete registeredBy[agreement];
        emit AgreementUnregistered(agreement);
    }

    /// @notice Trigger an inspection. Chainlink Functions queries the API
    ///         and calls `handleInspectionResult` back with the outcome.
    function requestInspection(address agreement, string calldata apiUrl) external returns (bytes32 requestId) {
        require(registeredBy[agreement] != address(0), "Not registered");

        bytes[] memory args = new bytes[](2);
        args[0] = abi.encode(apiUrl);
        args[1] = abi.encode(agreement);

        requestId = functionsClient.sendRequest(source, args, subscriptionId, GAS_LIMIT, donID);

        pendingRequests[requestId] = agreement;
        emit InspectionRequested(agreement, requestId);
    }

    /// @notice Chainlink Functions callback.
    function handleInspectionResult(bytes32 requestId, bytes memory response) external {
        address agreement = pendingRequests[requestId];
        require(agreement != address(0), "Unknown request");
        delete pendingRequests[requestId];

        uint256 passed = abi.decode(response, (uint256));
        bool ok = passed == 1;

        if (ok) {
            try IOracleConsumer(agreement).releaseDepositByOracle() {
                emit InspectionResult(agreement, true, true);
            } catch {
                emit InspectionResult(agreement, true, false);
            }
        } else {
            emit InspectionResult(agreement, false, false);
        }
    }

    /// @notice Admin — update Functions config.
    function setFunctionsConfig(address _router, uint64 _subscriptionId, bytes32 _donID) external onlyOwner {
        functionsRouter = _router;
        subscriptionId = _subscriptionId;
        donID = _donID;
    }
}
