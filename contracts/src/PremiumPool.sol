// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title PremiumPool
/// @notice Holds all collected premiums and protocol reserve.
///         Only the PayoutVault can withdraw funds for payouts.
///         The owner can deposit reserve capital.
contract PremiumPool {
    IERC20 public immutable cUSD;
    address public immutable owner;
    address public payoutVault;

    uint256 public totalDeposited;
    uint256 public totalPaidOut;

    event Deposited(address indexed from, uint256 amount);
    event PayoutVaultSet(address indexed vault);
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    error Unauthorized();
    error InsufficientBalance();
    error ZeroAmount();
    error VaultAlreadySet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != payoutVault) revert Unauthorized();
        _;
    }

    constructor(address _cUSD, address _owner) {
        cUSD = IERC20(_cUSD);
        owner = _owner;
    }

    /// @notice Set the PayoutVault address. Can only be called once.
    function setPayoutVault(address _vault) external onlyOwner {
        if (payoutVault != address(0)) revert VaultAlreadySet();
        payoutVault = _vault;
        emit PayoutVaultSet(_vault);
    }

    /// @notice Deposit reserve capital into the pool.
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        totalDeposited += amount;
        cUSD.transferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Called by PayoutVault to withdraw funds for a payout.
    function withdrawForPayout(uint256 amount, address recipient) external onlyVault {
        if (amount == 0) revert ZeroAmount();
        if (cUSD.balanceOf(address(this)) < amount) revert InsufficientBalance();
        totalPaidOut += amount;
        cUSD.transfer(recipient, amount);
        emit FundsWithdrawn(recipient, amount);
    }

    /// @notice Returns available balance in the pool.
    function availableBalance() external view returns (uint256) {
        return cUSD.balanceOf(address(this));
    }
}
