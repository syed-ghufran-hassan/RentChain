// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RentStreamToken is ERC20, Ownable {
    // The agreement allowed to forward rent into this contract
    address public immutable rentalAgreement;

    // Total amount of future rent tokenized (mint cap)
    uint256 public immutable totalFutureRent;

    // Cumulative rent received (informational)
    uint256 public totalRentDistributed;

    // Accumulator pattern
    uint256 public rewardPerTokenStored;
    uint256 private constant PRECISION = 1e18;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RentDistributed(uint256 amount, uint256 newRewardPerToken);
    event RewardClaimed(address indexed user, uint256 amount);

    modifier onlyAgreement() {
        require(msg.sender == rentalAgreement, "Only rental agreement");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _totalFutureRent,
        address _rentalAgreement,
        address initialOwner
    ) ERC20(name_, symbol_) Ownable(initialOwner) {
        require(_totalFutureRent > 0, "Invalid future rent");
        require(_rentalAgreement != address(0), "Invalid agreement");
        totalFutureRent = _totalFutureRent;
        rentalAgreement = _rentalAgreement;

        // Mint the entire supply to the owner (they sell/distribute tokens)
        _mint(initialOwner, _totalFutureRent);
    }

    /// Called by RentalAgreement.payRent() – forwards the rent for distribution
    function distributeRent() external payable onlyAgreement {
        require(msg.value > 0, "No rent sent");
        uint256 supply = totalSupply();
        require(supply > 0, "No tokens minted");

        totalRentDistributed += msg.value;
        rewardPerTokenStored += (msg.value * PRECISION) / supply;

        emit RentDistributed(msg.value, rewardPerTokenStored);
    }

    /// Current reward-per-token value
    function rewardPerToken() public view returns (uint256) {
        return rewardPerTokenStored;
    }

    /// Amount claimable by an account
    function earned(address account) public view returns (uint256) {
        uint256 delta = rewardPerTokenStored - userRewardPerTokenPaid[account];
        return (balanceOf(account) * delta) / PRECISION + rewards[account];
    }

    /// Holder claims accumulated rewards
    function claimReward() external {
        uint256 reward = earned(msg.sender);
        require(reward > 0, "Nothing to claim");

        rewards[msg.sender] = 0;
        userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;

        (bool sent, ) = msg.sender.call{value: reward}("");
        require(sent, "Transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    /// Update accumulator whenever balances change (mint/burn/transfer)
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            rewards[from] = earned(from);
            userRewardPerTokenPaid[from] = rewardPerTokenStored;
        }
        if (to != address(0)) {
            rewards[to] = earned(to);
            userRewardPerTokenPaid[to] = rewardPerTokenStored;
        }
        super._update(from, to, value);
    }

    receive() external payable {
        revert("Only via distributeRent");
    }
}