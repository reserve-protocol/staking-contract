# Generic Staked Appreciating Vault

The Staked Appreciating Vault is a simple ERC-4626 vault that allows users to deposit their assets and earn a yield on them. The yield is distributed in the same token as the deposited asset, making the vault token appreciate in value over time.

The vault distributes yield in epochs, or distribution periods. The distribution period is set at the time of vault deployment and can not be changed after. New rewards can be added to the vault at any time, however they will only start flowing at the beginning of the next epoch. Rewards are streamed to all users linearly during the distribution period.

The epochs run automatically and yield is auto-compounded with hooks on the `deposit`/`withdraw` functions. Additionally, adding new rewards is permissionless and can be done by either directly transferring the deposit token to the vault address or by calling the `addRewards` function. Once new rewards are added to the vault, they will be distributed to all users linearly during the next epoch.

### Dev

The implementation of the vault relies on an always increasing `totalAssets` value, the rate is calculated internally based on `totalAssets` per `totalSupply` which gives the exchange rate per unit of vault token. Additionally, the vault tackles inflation attacks with a decimal offset of `3` (equivalent to virtual shares offset of `1e3`).

# Generic Multi Rewards Vault

The Multi Rewards Vault is a simple ERC-4626 vault with transfers disabled, that allows the users to deposit an asset and receive rewards in one or multiple other tokens. New rewards are added by the vault owner and can be paid out instantly or over time.

The vault takes heavy inspiration from the following sources:

- [Synthetix - StakingRewards](https://github.com/Synthetixio/synthetix/blob/52d37c39632e9111250d4c68b5a1d973359135c3/contracts/StakingRewards.sol)
- [Curve - MultiRewards](https://github.com/curvefi/multi-rewards/blob/99995f90bd129bbe6b5a995daf6233fb79789e4e/contracts/MultiRewards.sol)
- [Fei - FlywheelStaticRewards & FlywheelCore](https://github.com/fei-protocol/flywheel-v2/blob/379c7385539034aac97bc18fc4189bf683e0805c/src/)
- [Popcorn DAO - MultiRewardStaking](https://github.com/Popcorn-Limited/contracts/blob/d029c413239735f58b0adcead11fdbe8f69a0e34/src/utils/MultiRewardStaking.sol)

This is a simplified implementation that keeps only the core functionality of the vaults and removes any additional features.
