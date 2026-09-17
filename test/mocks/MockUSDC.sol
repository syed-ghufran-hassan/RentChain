// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    constructor() ERC20("Mock USDC", "mUSDC") Ownable(msg.sender) {}

    /// @notice 6 decimals to mirror real USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Open faucet — mint test tokens to anyone.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
