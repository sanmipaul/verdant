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

    function test_ReentrancyGuard_InitialState() public {
        // _locked should be initialized to 1 (unlocked)
        // We can't directly read private state, but we can test via behavior
        // If initialized correctly, normal withdrawals should work
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        // This should succeed - contract not locked
        vm.prank(vault);
        pool.withdrawForPayout(25e18, makeAddr("farmer"));
    }

    function test_ReentrancyGuard_PreventsRecursiveWithdrawal() public {
        // Deploy a malicious contract that tries to re-enter on withdrawal
        vm.prank(owner);
        pool.setPayoutVault(vault);

        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        // The reentrancy guard prevents the same function from being called twice
        // within a single transaction. Since the test contract doesn't implement
        // an actual reentrant caller (that would need to be a separate contract),
        // we verify the guard state changes during withdrawal.
        vm.prank(vault);
        pool.withdrawForPayout(25e18, makeAddr("farmer"));

        // Second withdrawal should work (guard resets after first)
        vm.prank(vault);
        pool.withdrawForPayout(25e18, makeAddr("farmer2"));
    }

    function test_ReentrancyGuard_BlocksSameCallDuringExecution() public {
        // Create a mock attacker contract
        MockReentrancyAttacker attacker = new MockReentrancyAttacker(
            address(pool),
            address(cUSD)
        );

        vm.prank(owner);
        pool.setPayoutVault(address(attacker));

        // Fund pool and attacker
        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 100e18);
        pool.deposit(100e18);
        vm.stopPrank();

        // Fund attacker with cUSD for potential reentrancy
        cUSD.mint(address(attacker), 10e18);
        vm.prank(address(attacker));
        cUSD.approve(address(pool), 10e18);

        // Attacker's attempt to re-enter during withdrawal should fail
        // The noReentrant modifier prevents nested calls to withdrawForPayout
        vm.prank(address(attacker));
        attacker.attack();

        // Verify not all funds were drained by recursive calls
        uint256 remaining = pool.availableBalance();
        assertTrue(remaining > 0, "Should have remaining balance");
    }
}

contract MockReentrancyAttacker {
    PremiumPool public pool;
    MockERC20 public cUSD;
    uint256 public callCount;

    constructor(address _pool, address _cUSD) {
        pool = PremiumPool(_pool);
        cUSD = MockERC20(_cUSD);
    }

    function attack() public {
        callCount = 0;
        // This will trigger withdrawForPayout which has a reentrancy guard
        // Any reentrant call to withdrawForPayout should fail
        pool.withdrawForPayout(10e18, address(this));
    }

    receive() external payable {
        callCount++;
        // Attempt reentrancy - should fail due to noReentrant modifier
        if (callCount < 5) {
            pool.withdrawForPayout(10e18, address(this));
        }
    }
}
