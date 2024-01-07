// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {HappyVault} from "../src/HappyVault.sol";
import {HappyToken} from "../src/HappyToken.sol";
import {MockToken} from "../src/mock/MockToken.sol";
import {MerkleUtils} from "../src/utils/Merkle.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract HappyVaultTest is Test, MerkleUtils {
    uint256 constant DAY = 86_400;
    uint256 constant STAKE_AMOUNT = 100_000 ether;
    uint256 constant SALE_AMOUNT = 30_000 ether;
    uint256 constant PRICE = 1 ether;
    MockToken public payment_token;
    HappyToken public happy_token;
    HappyVault public happy_vault;

    function setUp() public {
        happy_token = new HappyToken();
        happy_vault = new HappyVault(address(happy_token));
        payment_token = new MockToken("Payment Token", "PAY");
    }

    function test_createOffering() public {
        happy_vault.createOffering(
            address(happy_token),
            address(payment_token),
            30 * DAY,
            SALE_AMOUNT,
            PRICE
        );
        assertEq(happy_vault.total_offerings(), 1);
    }

    function test_setRoot() public {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encode(address(this)));
        leaves[1] = keccak256(abi.encode(address(this)));
        bytes32 root = getRoot(leaves);
        happy_vault.setRoot(root);
        assertEq(happy_vault.root(), root);
        bytes32[] memory proof = getProof(leaves, 1);
        assertTrue(MerkleProof.verify(proof, root, leaves[1]));
    }

    function test_stake() public {
        test_createOffering();
        test_setRoot();
        assertEq(happy_vault.total_supply(), 0);
        assertEq(happy_vault.balances(address(this)), 0);
        happy_token.approve(address(happy_vault), STAKE_AMOUNT);
        happy_vault.stake(STAKE_AMOUNT);
        assertEq(happy_vault.total_supply(), STAKE_AMOUNT);
        assertEq(happy_vault.balances(address(this)), STAKE_AMOUNT);
        assertEq(happy_vault.deserved(0, address(this)), 0);
        vm.warp(block.timestamp + 31 * DAY);
        assertApproxEqAbs(
            happy_vault.deserved(0, address(this)),
            SALE_AMOUNT,
            1e6
        );
    }
}
