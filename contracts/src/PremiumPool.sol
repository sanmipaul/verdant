// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title PremiumPool
/// @notice Holds all collected premiums and protocol reserve.
///         Only the PayoutVault can withdraw funds for payouts.
///         The owner can deposit reserve capital.
/// @dev Gas optimizations: cached balance checks, batch operations, unchecked loops
/// @dev Security: Protected by reentrancy guard on withdrawForPayout
contract PremiumPool {
    IERC20 public immutable cUSD;
    address public immutable owner;
    address public payoutVault;

    uint256 public totalDeposited;
    uint256 public totalPaidOut;
    
    // Reentrancy guard: 1 = unlocked, 2 = locked
    uint256 private _locked;

    event Deposited(address indexed from, uint256 amount);
    event PayoutVaultSet(address indexed vault);
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    error Unauthorized();
    error InsufficientBalance();
    error ZeroAmount();
    error VaultAlreadySet();
    error Reentrancy();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != payoutVault) revert Unauthorized();
        _;
    }

    modifier noReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(address _cUSD, address _owner) {
        cUSD = IERC20(_cUSD);
        owner = _owner;
        _locked = 1;
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

    /// @notice Batch deposit multiple amounts (gas optimized).
    function batchDeposit(uint256[] calldata amounts) external {
        uint256 totalAmount;
        uint256 length = amounts.length;

        for (uint256 i = 0; i < length; ) {
            uint256 amount = amounts[i];
            if (amount == 0) revert ZeroAmount();
            totalAmount += amount;
            unchecked { i++; }
        }

        if (totalAmount == 0) revert ZeroAmount();
        totalDeposited += totalAmount;
        cUSD.transferFrom(msg.sender, address(this), totalAmount);
        emit Deposited(msg.sender, totalAmount);
    }

    /// @notice Called by PayoutVault to withdraw funds for a payout.
    /// @dev Protected by reentrancy guard to prevent recursive withdrawals
    function withdrawForPayout(uint256 amount, address recipient) external onlyVault noReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = cUSD.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();
        totalPaidOut += amount;
        cUSD.transfer(recipient, amount);
        emit FundsWithdrawn(recipient, amount);
    }

    /// @notice Returns available balance in the pool.
    function availableBalance() external view returns (uint256) {
        return cUSD.balanceOf(address(this));
    }
}
