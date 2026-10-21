// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ProofHouse} from "../src/ProofHouse.sol";

/// @dev Complements the basic ERC-20 tests with allowance lifecycles, boundary
/// values, and recovery after rejected operations. All funds come from the
/// constructor mint; the tests never edit token storage or mint through a harness.
/// forge-config: default.fuzz.runs = 1024
contract ProofHouseAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ProofHouse private token;
    address private holder;
    address private recipient;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ProofHouse();
        holder = makeAddr("adversarial holder");
        recipient = makeAddr("adversarial recipient");
        spender = makeAddr("adversarial spender");
    }

    function test_oneBaseUnitCanMakeADirectAndDelegatedRoundTrip() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), holder, 1);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, address(this), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, address(this), 1));

        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAmountCannotWrapBalancesEvenWithUnlimitedApproval() public {
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(holder, type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), holder, type(uint256).max);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceDecreasesOnFullSupplySpend() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));

        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferDoesNotBypassBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);

        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferDoesNotBypassAuthorization() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), address(this), 1);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmitsEventAndPreservesExistingAllowance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 0));

        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroRejectsUnlimitedSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);

        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 amount, bool unlimited) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), approved);

        // No new approval: failed spending must leave the original usable.
        assertTrue(token.transfer(holder, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_returningTokensDoesNotReviveExhaustedAllowance(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(holder, amount));
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 0);

        // The holder remains able to move its own funds without an allowance.
        vm.prank(holder);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unlimitedApprovalCanBeRevokedAndReplaced(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, amount));
        vm.prank(holder);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(address(this), holder, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, amount));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalIsAbsoluteIdempotentAndIsolated(uint256 initial, uint256 replacement) public {
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(recipient, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 2));

        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(address(this), spender, replacement);
            assertTrue(token.approve(spender, replacement));
            assertEq(token.allowance(address(this), spender), replacement);
        }
        assertEq(token.allowance(address(this), recipient), 1);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferPartitionAndRoundTripAreExact(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 1, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        assertTrue(token.transfer(holder, firstPart));
        assertTrue(token.transfer(holder, amount - firstPart));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
