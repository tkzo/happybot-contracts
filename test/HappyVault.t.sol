// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {HappyVault} from "../src/HappyVault.sol";
import {HappyToken} from "../src/HappyToken.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract HappyVaultTest is Test {
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

    function test_addToWhitelist() public {
        address[] memory whitelist = new address[](1);
        whitelist[0] = address(this);
        happy_vault.addToWhitelist(whitelist);
        assertEq(happy_vault.whitelist(address(this)), true);
    }

    function test_stake() public {
        test_createOffering();
        test_addToWhitelist();
        assertEq(happy_vault.total_supply(), 0);
        assertEq(happy_vault.balances(address(this)), 0);
        happy_token.approve(address(happy_vault), STAKE_AMOUNT);
        happy_vault.stake(STAKE_AMOUNT);
        assertEq(happy_vault.total_supply(), STAKE_AMOUNT);
        assertEq(happy_vault.balances(address(this)), STAKE_AMOUNT);
        assertEq(happy_vault.deserved(0, address(this)), 0);
        vm.warp(block.timestamp + 31 * DAY);
        assertGe(happy_vault.deserved(0, address(this)), SALE_AMOUNT - 1 ether);
    }
}
