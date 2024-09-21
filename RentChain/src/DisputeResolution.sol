// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DisputeResolution {
    // Enum to represent the status of a dispute
    enum DisputeStatus { Pending, Resolved, Rejected }

    // Struct to represent a dispute
    struct Dispute {
        address tenant;          // Address of the tenant raising the dispute
        address owner;           // Address of the property owner involved in the dispute
        string reason;          // Reason for raising the dispute
        DisputeStatus status;    // Current status of the dispute (Pending, Resolved, Rejected)
        uint256 propertyId;      // ID of the property related to the dispute
        uint256 amount;          // The amount in dispute, typically the security deposit
    }

    // Array to store all disputes
    Dispute[] public disputes;
    
    // Address of the designated arbitrator who resolves disputes
    address public arbitrator;

    // Events to log important actions in the contract
    event DisputeCreated(
        uint256 disputeId, 
        address tenant, 
        address owner, 
        uint256 propertyId, 
        string reason, 
        uint256 amount
    );

    // Events when dispute resolved

    event DisputeResolved(uint256 disputeId, DisputeStatus status);

    // Modifier to restrict access to the arbitrator
    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Only arbitrator can resolve disputes");
        _;
    }

    // Constructor to set the arbitrator's address
    constructor(address _arbitrator) {
        arbitrator = _arbitrator; // Set the arbitrator during contract deployment
    }

    // Function to create a dispute
    function createDispute(address _owner, uint256 _propertyId, string memory _reason, uint256 _amount) public {
        // Push a new dispute to the disputes array
        disputes.push(Dispute({
            tenant: msg.sender,     // The address of the tenant creating the dispute
            owner: _owner,          // The address of the property owner
            reason: _reason,        // The reason for the dispute
            status: DisputeStatus.Pending, // Set the initial status to Pending
            propertyId: _propertyId, // The ID of the property in dispute
            amount: _amount         // The amount involved in the dispute
        }));

        // Emit an event to log the creation of the dispute
        emit DisputeCreated(disputes.length - 1, msg.sender, _owner, _propertyId, _reason, _amount);
    }

    // Function for the arbitrator to resolve a dispute
    function resolveDispute(uint256 _disputeId, DisputeStatus _status) public onlyArbitrator {
        // Load the dispute from the disputes array
        Dispute storage dispute = disputes[_disputeId];

        // Ensure the dispute is still pending
        require(dispute.status == DisputeStatus.Pending, "Dispute is already resolved");

        // Update the status of the dispute
        dispute.status = _status;

        // Emit an event to log the resolution of the dispute
        emit DisputeResolved(_disputeId, _status);
    }

    // Function to retrieve a specific dispute's details
    function getDispute(uint256 _disputeId) public view returns (Dispute memory) {
        return disputes[_disputeId]; // Return the dispute at the specified index
    }

    // Function to get the total number of disputes created
    function getTotalDisputes() public view returns (uint256) {
        return disputes.length; // Return the length of the disputes array
    }
}
