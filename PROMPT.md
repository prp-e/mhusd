# ChatGPT/Claude Prompt

## Token

Based on the following OpenZeppelin TRC20 Contract: 

```solidity
// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin TRON Contracts ^5.6.0
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/tron-contracts/access/Ownable.sol";
import {TRC20} from "@openzeppelin/tron-contracts/token/TRC20/TRC20.sol";
import {TRC20Burnable} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Burnable.sol";
import {TRC20Permit} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Permit.sol";

contract MuhammadrezaHaghiriSUSD is TRC20, TRC20Burnable, Ownable, TRC20Permit {
    constructor(address initialOwner)
        TRC20("Muhammadreza Haghiri's USD", "MHUSD")
        Ownable(initialOwner)
        TRC20Permit("Muhammadreza Haghiri's USD")
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}


```

Make a token with these features:

- My wallet is admin account. 
- It is an algorithmic stablecoin and allign its own price and keeps it exactly at $1. 
- For minting each one unit, there must be a %0.05 minting fee in vault (admin account). 
- When user wants to turn it back to TRX, the TRX they have paid in vault will be returned to them and the tokens will be burned. 
- Also the logo is : https://github.com/prp-e/mhusd/blob/main/mhusd.png?raw=true. Add the logo somewhere because it being shown in the tronscan is beautiful. 

Put the final contract in one single block of code and for each function and method, provide a complete comment guide.