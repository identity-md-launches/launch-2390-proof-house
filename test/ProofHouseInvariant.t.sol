// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProofHouse} from "../src/ProofHouse.sol";
import {TokenHandler} from "./helpers/TokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract ProofHouseInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ProofHouse private token;
    TokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new ProofHouse();
        actors = [makeAddr("actor one"), makeAddr("actor two"), makeAddr("actor three"), makeAddr("actor four")];
        token.transfer(actors[0], SUPPLY);
        handler = new TokenHandler(token, actors, SUPPLY);

        // Start with several funded holders, one empty holder, and both finite
        // and unlimited approvals so delegated calls exercise useful state early.
        handler.move(0, 1, SUPPLY / 4);
        handler.move(0, 2, SUPPLY / 4);
        handler.approve(0, 1, SUPPLY / 4);
        handler.approveUnlimited(1, 2);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.approveUnlimited.selector;
        selectors[4] = TokenHandler.revoke.selector;
        selectors[5] = TokenHandler.rejectTransferOverBalance.selector;
        selectors[6] = TokenHandler.rejectSpendOverLimit.selector;
        selectors[7] = TokenHandler.rejectTransferToZero.selector;
        selectors[8] = TokenHandler.rejectSpendToZero.selector;
        selectors[9] = TokenHandler.rejectApprovalToZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchOnlyAuthorizedActions() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev After any random history, each holder can still transfer its entire
    /// balance. Rejected spends and revoked approvals must never freeze a holder.
    function afterInvariant() public {
        for (uint256 i; i < actors.length; ++i) {
            handler.move(i, 0, handler.expectedBalance(actors[i]));
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_supplyAndAllBalancesAreConserved();
        invariant_allowancesMatchOnlyAuthorizedActions();
    }
}
