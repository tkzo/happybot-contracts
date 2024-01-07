// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract HappyToken is ERC20 {
    constructor() ERC20("Happy Token", "HAPPY") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}
