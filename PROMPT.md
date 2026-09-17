# ChatGPT/Claude Prompt

## Token

Based on the following OpenZeppelin TRC20 Contract: 

```solidity
// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin TRON Contracts ^5.6.0
pragma solidity ^0.8.26;

import {TRC20} from "@openzeppelin/tron-contracts/token/TRC20/TRC20.sol";
import {TRC20Permit} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Permit.sol";

contract MuhammadrezaHaghiriSUSD is TRC20, TRC20Permit {
    constructor()
        TRC20("Muhammadreza Haghiri's USD", "MHUSD")
        TRC20Permit("Muhammadreza Haghiri's USD")
    {}
}
```

Make a token with these features: