// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MaintenanceRequest {
    enum RequestStatus { Pending, Resolved, Rejected }

    struct Request {
        address tenant;           // Address of the tenant submitting the request
        uint256 propertyId;       // ID of the property related to the request
        string description;       // Description of the maintenance issue
        RequestStatus status;     // Current status of the request
        uint256 createdAt;        // Timestamp when the request was created
    }

    Request[] public requests;    // Array to store all maintenance requests

    event RequestCreated(uint256 requestId, address tenant, uint256 propertyId, string description);
    event RequestResolved(uint256 requestId, RequestStatus status);

    // Function to create a maintenance request
    function createRequest(uint256 _propertyId, string memory _description) public {
        requests.push(Request({
            tenant: msg.sender,
            propertyId: _propertyId,
            description: _description,
            status: RequestStatus.Pending,
            createdAt: block.timestamp
        }));

        emit RequestCreated(requests.length - 1, msg.sender, _propertyId, _description);
    }

    // Function for the property owner to resolve a maintenance request
    function resolveRequest(uint256 _requestId, RequestStatus _status) public {
        Request storage request = requests[_requestId];
        require(request.status == RequestStatus.Pending, "Request is already resolved");

        request.status = _status;
        emit RequestResolved(_requestId, _status);
    }

    // Function to view a specific maintenance request
    function getRequest(uint256 _requestId) public view returns (Request memory) {
        return requests[_requestId];
    }

    // Function to get the total number of maintenance requests
    function getTotalRequests() public view returns (uint256) {
        return requests.length;
    }
}
