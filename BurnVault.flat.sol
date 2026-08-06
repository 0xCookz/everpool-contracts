// SPDX-License-Identifier: MIT
pragma solidity =0.8.26 >=0.4.16;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/EverpoolBurnVault.sol

/// @title EverpoolBurnVault
/// @notice The fee recipient for every token launched through the Everpool launchpad. pools.trade
///         pushes the creator's fee share here (in the launched token and in native ETH) and calls
///         `onAmountsReceived`. Anyone can then call `burn()` to send those fees to the dead address,
///         permanently removing them from supply. 100% of the creator share is burned — the dev takes
///         nothing. (pools.trade still autocompounds its own ~80% into the locked pool.)
/// @dev    Prototype — not audited. v1 sends fees straight to 0x…dEaD. A v2 can swap the ETH side into
///         the token first (a true buyback) so even more of the token is burned.
contract EverpoolBurnVault {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    event Burned(address indexed currency, uint256 amount);

    /// @notice pools.trade fee callback — fees are already pushed to this contract; accept the notice.
    function onAmountsReceived(uint256, uint256, uint256) external {}

    /// @notice Burn every accrued fee of `currency` (use address(0) for native ETH). Permissionless.
    /// @return amount the amount burned
    function burn(address currency) external returns (uint256 amount) {
        if (currency == address(0)) {
            amount = address(this).balance;
            if (amount > 0) {
                (bool ok,) = DEAD.call{value: amount}("");
                require(ok, "burn eth failed");
            }
        } else {
            amount = IERC20(currency).balanceOf(address(this));
            if (amount > 0) IERC20(currency).transfer(DEAD, amount);
        }
        if (amount > 0) emit Burned(currency, amount);
    }

    receive() external payable {}
}
