// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RentChainLending is Ownable, ReentrancyGuard {
    // ---------- Constants ----------
    uint256 public constant LTV_BPS = 5000; // 50%
    uint256 public constant LIQUIDATION_THRESHOLD_BPS = 7500; // 75%
    uint256 public constant LIQUIDATION_PENALTY_BPS = 1000; // 10%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant INTEREST_RATE_BPS = 1000; // 10% APR

    // ---------- State ----------
    IERC721 public immutable propertyNFT;
    IERC20 public immutable loanToken;

    struct Loan {
        address borrower;
        uint256 tokenId;
        uint256 principal; // borrowed amount
        uint256 collateralValue; // appraisal at borrow time
        uint256 borrowedAt; // timestamp
        uint256 repaid; // cumulative repayment
        bool active;
    }

    mapping(uint256 => Loan) public loans; // tokenId => Loan
    mapping(uint256 => bool) public collateralLocked;

    // ---------- Events ----------
    event CollateralDeposited(address indexed borrower, uint256 indexed tokenId, uint256 appraisedValue);
    event Borrowed(address indexed borrower, uint256 indexed tokenId, uint256 amount);
    event Repaid(address indexed borrower, uint256 indexed tokenId, uint256 amount, uint256 remaining);
    event CollateralWithdrawn(address indexed borrower, uint256 indexed tokenId);
    event Liquidated(address indexed liquidator, address indexed borrower, uint256 indexed tokenId, uint256 debtRepaid);

    modifier onlyBorrower(uint256 tokenId) {
        require(loans[tokenId].borrower == msg.sender, "Not borrower");
        _;
    }

    constructor(address _propertyNFT, address _loanToken) Ownable(msg.sender) {
        require(_propertyNFT != address(0), "Invalid NFT");
        require(_loanToken != address(0), "Invalid token");
        propertyNFT = IERC721(_propertyNFT);
        loanToken = IERC20(_loanToken);
    }

    // ---------- Collateral ----------

    /// @notice Deposit a PropertyNFT as collateral with an appraised value.
    ///         The appraisal is set by the borrower for local testing; in
    ///         production this would come from an oracle.
    function depositCollateral(uint256 tokenId, uint256 appraisedValue) external nonReentrant {
        require(!collateralLocked[tokenId], "Already locked");
        require(appraisedValue > 0, "Invalid appraisal");
        require(propertyNFT.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        // Transfer NFT into the lending contract
        propertyNFT.transferFrom(msg.sender, address(this), tokenId);

        collateralLocked[tokenId] = true;
        loans[tokenId] = Loan({
            borrower: msg.sender,
            tokenId: tokenId,
            principal: 0,
            collateralValue: appraisedValue,
            borrowedAt: 0,
            repaid: 0,
            active: false
        });

        emit CollateralDeposited(msg.sender, tokenId, appraisedValue);
    }

    // ---------- Borrow ----------

    function borrow(uint256 tokenId, uint256 amount) external onlyBorrower(tokenId) nonReentrant {
        Loan storage loan = loans[tokenId];
        require(!loan.active, "Loan active");
        require(amount > 0, "Amount zero");

        // Check LTV
        uint256 maxBorrow = (loan.collateralValue * LTV_BPS) / BPS_DENOMINATOR;
        require(amount <= maxBorrow, "Exceeds LTV");

        // Check pool has liquidity
        require(loanToken.balanceOf(address(this)) >= amount, "Insufficient pool liquidity");

        loan.principal = amount;
        loan.borrowedAt = block.timestamp;
        loan.repaid = 0;
        loan.active = true;

        require(loanToken.transfer(msg.sender, amount), "Transfer failed");
        emit Borrowed(msg.sender, tokenId, amount);
    }

    // ---------- Repay ----------

    function repay(uint256 tokenId, uint256 amount) external onlyBorrower(tokenId) nonReentrant {
        Loan storage loan = loans[tokenId];
        require(loan.active, "No active loan");
        require(amount > 0, "Amount zero");

        uint256 owed = currentDebt(tokenId);
        uint256 pay = amount > owed ? owed : amount;

        require(loanToken.transferFrom(msg.sender, address(this), pay), "TransferFrom failed");

        loan.repaid += pay;

        if (loan.repaid >= owed) {
            loan.active = false;
            emit Repaid(msg.sender, tokenId, pay, 0);
        } else {
            emit Repaid(msg.sender, tokenId, pay, owed - pay);
        }
    }

    // ---------- Withdraw Collateral ----------

    function withdrawCollateral(uint256 tokenId) external onlyBorrower(tokenId) nonReentrant {
        Loan storage loan = loans[tokenId];
        require(!loan.active, "Loan still active");
        require(collateralLocked[tokenId], "No collateral");

        collateralLocked[tokenId] = false;
        propertyNFT.transferFrom(address(this), loan.borrower, tokenId);

        delete loans[tokenId];
        emit CollateralWithdrawn(msg.sender, tokenId);
    }

    // ---------- Liquidation ----------

    function liquidate(uint256 tokenId) external nonReentrant {
        Loan storage loan = loans[tokenId];
        require(loan.active, "No active loan");

        uint256 debt = currentDebt(tokenId);
        uint256 ratioBps = (debt * BPS_DENOMINATOR) / loan.collateralValue;
        require(ratioBps >= LIQUIDATION_THRESHOLD_BPS, "Not liquidatable");

        uint256 penalty = (debt * LIQUIDATION_PENALTY_BPS) / BPS_DENOMINATOR;
        uint256 totalDue = debt + penalty;

        require(loanToken.transferFrom(msg.sender, address(this), totalDue), "Payment failed");

        // Transfer NFT to liquidator
        address borrower = loan.borrower;
        collateralLocked[tokenId] = false;
        propertyNFT.transferFrom(address(this), msg.sender, tokenId);

        delete loans[tokenId];
        emit Liquidated(msg.sender, borrower, tokenId, totalDue);
    }

    // ---------- Views ----------

    /// @notice Current debt including accrued interest.
    function currentDebt(uint256 tokenId) public view returns (uint256) {
        Loan memory loan = loans[tokenId];
        if (!loan.active || loan.borrowedAt == 0) return 0;

        uint256 elapsed = block.timestamp - loan.borrowedAt;
        uint256 interest = (loan.principal * INTEREST_RATE_BPS * elapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);

        uint256 total = loan.principal + interest;
        uint256 remaining = total > loan.repaid ? total - loan.repaid : 0;
        return remaining;
    }

    /// @notice Current loan-to-value ratio in basis points.
    function currentLtvBps(uint256 tokenId) external view returns (uint256) {
        Loan memory loan = loans[tokenId];
        if (loan.collateralValue == 0) return 0;
        return (currentDebt(tokenId) * BPS_DENOMINATOR) / loan.collateralValue;
    }

    /// @notice Max amount the borrower can draw right now.
    function maxBorrow(uint256 tokenId) external view returns (uint256) {
        Loan memory loan = loans[tokenId];
        return (loan.collateralValue * LTV_BPS) / BPS_DENOMINATOR;
    }

    /// @notice Owner funds the pool with loan tokens (lender role).
    function fundPool(uint256 amount) external onlyOwner {
        require(loanToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }
}
