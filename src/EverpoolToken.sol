// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title EverpoolToken
/// @notice Fixed-supply ERC20 minted once, in full, to the launcher at creation.
///         The entire supply is seeded into the token's Uniswap v4 pool at launch;
///         there is no mint function, no owner, and no way to inflate supply later.
contract EverpoolToken is ERC20 {
    /// @param name_     Token name (e.g. "Everpool")
    /// @param symbol_   Token symbol (e.g. "POOL")
    /// @param supply    Total fixed supply (in wei, 18 decimals)
    /// @param recipient The launcher, which seeds the pool with this supply
    constructor(string memory name_, string memory symbol_, uint256 supply, address recipient)
        ERC20(name_, symbol_)
    {
        require(recipient != address(0), "recipient=0");
        require(supply > 0, "supply=0");
        _mint(recipient, supply);
    }
}
