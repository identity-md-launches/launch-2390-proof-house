// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ProofHouse} from "../../src/ProofHouse.sol";

/// @dev Local test helper, not a production launch contract.
contract FactoryProbe {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (ProofHouse) {
        return new ProofHouse{salt: salt}();
    }

    function send(ProofHouse token, address to, uint256 amount) external {
        require(msg.sender == controller, "test controller only");
        require(token.transfer(to, amount), "transfer failed");
    }
}
