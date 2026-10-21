// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProofHouse} from "../src/ProofHouse.sol";
import {FactoryProbe} from "./helpers/FactoryProbe.sol";

contract ProofHouseLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    FactoryProbe private factory;

    function setUp() public {
        factory = new FactoryProbe();
    }

    function testFuzz_create2MintsToFactoryInsteadOfCaller(address caller, bytes32 salt) public {
        vm.assume(caller != address(0) && caller != address(factory));
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(ProofHouse).creationCode))
                    )
                )
            )
        );

        vm.prank(caller);
        ProofHouse token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Checks token accounting along launch/claim/trading paths. This does not simulate AMM pricing.
    function test_factoryDistributionClaimsAndPoolTransfersDeliverFullAmounts() public {
        ProofHouse token = factory.deploy(keccak256("launch accounting"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager");
        address remainder = makeAddr("requester remainder");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainderShare = SUPPLY - swarmShare - poolShare;
        factory.send(token, distributor, swarmShare);
        factory.send(token, pool, poolShare);
        factory.send(token, remainder, remainderShare);

        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        uint256 purchased = 123_456 ether;
        vm.prank(pool);
        assertTrue(token.transfer(trader, purchased));
        assertEq(token.balanceOf(trader), purchased);
        assertEq(token.balanceOf(pool), poolShare - purchased);

        vm.prank(trader);
        assertTrue(token.transfer(pool, purchased));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.balanceOf(claimant) + token.balanceOf(pool) + token.balanceOf(remainder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
