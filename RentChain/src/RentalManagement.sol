// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RentalManagement {
    // Struct to store property details
    struct Property {
        address owner; // Owner of the property
        string name; // Name of the property
        string location; // Location of the property
        uint256 rentPerMonth; // Monthly rent amount
        bool isRented; // Status to indicate if the property is currently rented
    }

    // Struct to store rental agreement details
    struct RentalAgreement {
        address tenant; // Address of the tenant
        uint256 propertyId; // ID of the rented property
        uint256 deposit; // Security deposit amount
        uint256 rentalStart; // Start timestamp of the rental period
        uint256 rentalEnd; // End timestamp of the rental period
    }

    // Dynamic array to store all properties
    Property[] public properties;

    // Mapping of property ID to rental agreements
    mapping(uint256 => RentalAgreement) public rentalAgreements;

    // Events to log important actions for better transparency and off-chain tracking
    event PropertyRegistered(
        uint256 propertyId,
        address owner,
        string name,
        string location,
        uint256 rentPerMonth
    );
    event PropertyRented(
        uint256 propertyId,
        address tenant,
        uint256 rentalStart,
        uint256 rentalEnd
    );
    event DepositReturned(
        uint256 propertyId,
        address tenant,
        uint256 amount
    );

    // Modifier to restrict access to only the property owner
    modifier onlyOwner(uint256 _propertyId) {
        require(
            msg.sender == properties[_propertyId].owner,
            "Not property owner"
        );
        _;
    }

    // Modifier to restrict access to only the tenant of a property
    modifier onlyTenant(uint256 _propertyId) {
        require(
            msg.sender == rentalAgreements[_propertyId].tenant,
            "Not tenant"
        );
        _;
    }

    // Function to register a new property
    // Takes property details such as name, location, and rent per month as input
    function registerProperty(
        string memory _name,
        string memory _location,
        uint256 _rentPerMonth
    ) public {
        // Add a new property to the properties array
        properties.push(Property(msg.sender, _name, _location, _rentPerMonth, false));

        // Emit an event to log the property registration
        uint256 propertyId = properties.length - 1;
        emit PropertyRegistered(propertyId, msg.sender, _name, _location, _rentPerMonth);
    }

    // Function to rent a property
    // Tenant needs to specify the property ID, rental start time, and rental end time
    // Must send sufficient rent and deposit
    function rentProperty(
        uint256 _propertyId,
        uint256 _rentalStart,
        uint256 _rentalEnd
    ) public payable {
        // Load the property based on the given ID
        Property storage property = properties[_propertyId];

        // Ensure the property is not already rented
        require(!property.isRented, "Property is already rented");

        // Ensure sufficient rent is sent with the transaction
        require(msg.value >= property.rentPerMonth, "Insufficient rent");

        // Set deposit as one month's rent and ensure it is paid
        uint256 deposit = property.rentPerMonth;
        require(msg.value >= deposit, "Deposit required");

        // Create a rental agreement for the property
        rentalAgreements[_propertyId] = RentalAgreement(
            msg.sender,
            _propertyId,
            deposit,
            _rentalStart,
            _rentalEnd
        );

        // Mark the property as rented
        property.isRented = true;

        // Emit an event to log the rental action
        emit PropertyRented(_propertyId, msg.sender, _rentalStart, _rentalEnd);
    }

    // Function for the property owner to return the security deposit to the tenant
    // Can only be called after the rental period ends
    function returnDeposit(uint256 _propertyId) public onlyOwner(_propertyId) {
        // Load the rental agreement for the property
        RentalAgreement storage agreement = rentalAgreements[_propertyId];

        // Ensure the rental period has ended
        require(block.timestamp > agreement.rentalEnd, "Rental period not ended");

        // Transfer the deposit back to the tenant
        payable(agreement.tenant).transfer(agreement.deposit);

        // Emit an event to log the deposit return
        emit DepositReturned(_propertyId, agreement.tenant, agreement.deposit);
    }

    // Function to view all properties
    // Returns the entire properties array
    function viewProperties() public view returns (Property[] memory) {
        return properties;
    }
}
