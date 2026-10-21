// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Proof House (PH)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative privileges.
contract ProofHouse is ERC20 {
    /// @notice One billion PH, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Mints the entire supply exactly once to the immediate deployer.
    ///      When deployed through the launch factory, the factory receives it all.
    constructor() ERC20("Proof House", "PH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
