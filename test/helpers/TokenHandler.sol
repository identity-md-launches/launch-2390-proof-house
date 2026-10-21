// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ProofHouse} from "../../src/ProofHouse.sol";

/// @dev Stateful test driver with a separate model of balances and approvals.
/// Failed operations deliberately leave the model unchanged: the invariants then
/// check rollback of every tracked balance and allowance after each handler call.
contract TokenHandler is Test {
    ProofHouse private immutable token;
    address[4] private actors;

    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ProofHouse token_, address[4] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply;
    }

    function move(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        _approve(ownerIndex, spenderIndex, amount);
    }

    // Explicit actions make both sides of the unlimited/finite boundary and
    // revocation reachable without relying on a random uint256 hitting them.
    function approveUnlimited(uint256 ownerIndex, uint256 spenderIndex) external {
        _approve(ownerIndex, spenderIndex, type(uint256).max);
    }

    function revoke(uint256 ownerIndex, uint256 spenderIndex) external {
        _approve(ownerIndex, spenderIndex, 0);
    }

    function _approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) private {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectTransferOverBalance(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[from];
        // All balances are at most the fixed supply, so balance + 1 cannot overflow.
        amount = bound(amount, balance + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectSpendOverLimit(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];

        if (allowed <= balance) {
            // This includes spending again after a revoke or exhausted allowance.
            amount = bound(amount, allowed + 1, type(uint256).max);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        } else {
            // Authorization exists but funds do not. A revert must restore the
            // allowance even when transferFrom tried to spend it before moving funds.
            amount = bound(amount, balance + 1, allowed);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
        }
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferToZero(uint256 fromIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
    }

    function rejectSpendToZero(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function rejectApprovalToZero(uint256 ownerIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }
}
