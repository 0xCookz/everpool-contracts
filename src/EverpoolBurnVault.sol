// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
