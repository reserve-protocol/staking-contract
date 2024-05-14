// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC4626, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC4626Router {
    error ERC4626Router__InvalidOptions();
    error ERC4626Router__InvalidVaultChain();

    /**
     * @notice Deposits into a list of chained ERC4626 vaults.
     * @param vaults List of ERC4626 compatible vaults to deposit into.
     * @param amount The initial amount to be deposited in the first vault.
     * @dev Every following vault must have the previous vault as the underlying.
     */
    function depositChained(IERC4626[] memory vaults, uint256 amount) external {
        uint256 vaultCount = vaults.length;

        // Let's make sure there's vaults and amounts to deposit.
        if (vaultCount == 0 || amount == 0) {
            revert ERC4626Router__InvalidOptions();
        }

        // While looping through the vaults...
        for (uint256 i = 0; i < vaultCount; i++) {
            // Let's get the vault and asset details
            IERC4626 vault = vaults[i];
            IERC20 asset = IERC20(vault.asset());

            // If it's the first vault, we need to transfer the base asset to the contract
            if (i == 0) {
                SafeERC20.safeTransferFrom(asset, msg.sender, address(this), amount);
            }

            // Figure out the deposit amount for the vault
            // Note: This also accounts for any assets that were transferred to the contract
            uint256 depositAmount = asset.balanceOf(address(this));
            SafeERC20.forceApprove(asset, address(vault), depositAmount);

            if (i != vaultCount - 1) {
                // If it's not the last vault, we deposit while minting to the contract.
                vault.deposit(depositAmount, address(this));

                // Let's make sure the asset required for the next vault is actually the vault we're depositing into.
                if (vaults[i + 1].asset() != address(vault)) {
                    revert ERC4626Router__InvalidVaultChain();
                }
            } else {
                // If it's the last vault, we deposit minting directly to the user.
                vault.deposit(depositAmount, msg.sender);
            }
        }
    }
}
