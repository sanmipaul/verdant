// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PremiumPool} from "../src/PremiumPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PremiumPoolTest is Test {
    PremiumPool public pool;
    MockERC20   public cUSD;

    address public owner   = makeAddr("owner");
    address public vault   = makeAddr("vault");
    address public sponsor = makeAddr("sponsor");
    address public other   = makeAddr("other");

    function setUp() public {
        cUSD = new MockERC20("Celo Dollar", "cUSD", 18);
        pool = new PremiumPool(address(cUSD), owner);

        cUSD.mint(sponsor, 500e18);
        cUSD.mint(other, 100e18);
    }

    function test_Deposit() public {
        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        assertEq(pool.availableBalance(), 100e18);
        assertEq(pool.totalDeposited(), 100e18);
    }

    function test_CannotDepositZero() public {
        vm.expectRevert(PremiumPool.ZeroAmount.selector);
        vm.prank(sponsor);
        pool.deposit(0);
    }

    function test_SetPayoutVault_OnlyOwner() public {
        vm.expectRevert(PremiumPool.Unauthorized.selector);
        vm.prank(other);
        pool.setPayoutVault(vault);
    }

    function test_SetPayoutVault_OnlyOnce() public {
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.expectRevert(PremiumPool.VaultAlreadySet.selector);
        vm.prank(owner);
        pool.setPayoutVault(makeAddr("vault2"));
    }

    function test_WithdrawForPayout_OnlyVault() public {
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        vm.expectRevert(PremiumPool.Unauthorized.selector);
        vm.prank(other);
        pool.withdrawForPayout(10e18, other);
    }

    function test_WithdrawForPayout_Success() public {
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        address farmer = makeAddr("farmer");
        uint256 farmerBefore = cUSD.balanceOf(farmer);

        vm.prank(vault);
        pool.withdrawForPayout(25e18, farmer);

        assertEq(cUSD.balanceOf(farmer), farmerBefore + 25e18);
        assertEq(pool.availableBalance(), 75e18);
        assertEq(pool.totalPaidOut(), 25e18);
    }

    function test_CannotWithdrawMoreThanBalance() public {
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 10e18);
        pool.deposit(10e18);
        vm.stopPrank();

        vm.expectRevert(PremiumPool.InsufficientBalance.selector);
        vm.prank(vault);
        pool.withdrawForPayout(50e18, makeAddr("farmer"));
    }

    function test_AvailableBalanceReflectsMultipleDeposits() public {
        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 200e18);
        pool.deposit(100e18);
        pool.deposit(50e18);
        vm.stopPrank();

        assertEq(pool.availableBalance(), 150e18);
        assertEq(pool.totalDeposited(), 150e18);
    }
}
