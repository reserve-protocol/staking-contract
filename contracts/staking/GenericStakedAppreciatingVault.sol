// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626, IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct RewardTracker {
    uint256 rewardPeriodStart; // {s}
    uint256 rewardPeriodEnd; // {s}
    uint256 rewardAmount; // {qAsset}
}

/**
 * @title GenericMultiRewardsVault
 * @notice Transferrable ERC4626 vault with linear reward streaming in the vault's asset token.
 *         The only reward token is the asset itself. Adding rewards is permisionless.
 * @dev Asset tokens transferred into the contract without `deposit` will be picked up as part of
 *      the next week distribution period. Any token transferred into the contract that is not
 *      the asset token will be lost forever.
 *
 * Unit Notation
 *   - {qAsset} = Asset token quanta
 *   - {qShare} = Share token quanta
 *   - {s} = Seconds
 */
contract GenericStakedAppreciatingVault is ERC4626 {
    uint256 public immutable DISTRIBUTION_PERIOD; // {s}

    RewardTracker public rewardTracker;
    uint256 private totalDeposited; // {qAsset}

    event RewardDistributionUpdated(uint256 periodStart, uint256 periodEnd, uint256 amount);

    /**
     * @param _name Vault Name
     * @param _symbol Vault Symbol
     * @param _underlying {qAsset} Asset Token
     * @param _distributionPeriod {s} Distribution Period for Accumulated Rewards
     */
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying,
        uint256 _distributionPeriod
    ) ERC4626(_underlying) ERC20(_name, _symbol) {
        DISTRIBUTION_PERIOD = _distributionPeriod;

        _updateRewards();
    }

    function _updateRewards() internal {
        IERC20 _asset = IERC20(asset());

        uint256 accountedRewards = _currentAccountedRewards();
        totalDeposited = totalDeposited + accountedRewards;

        if (block.timestamp < rewardTracker.rewardPeriodEnd) {
            // We're only scaling the current distribution reward amount to the current total assets,
            // without adding any new unaccounted rewards.

            rewardTracker.rewardAmount = rewardTracker.rewardAmount - accountedRewards;
        } else {
            // The current distribution period has ended, so we're adding the unaccounted rewards
            // to the next distribution period starting now.

            uint256 allAvailableAssets = _asset.balanceOf(address(this));
            uint256 rewardsToBeDistributed = allAvailableAssets - totalDeposited;
            rewardTracker.rewardPeriodEnd = block.timestamp + DISTRIBUTION_PERIOD;
            rewardTracker.rewardAmount = rewardsToBeDistributed;
        }

        // Either way, we're tracking the distribution from now.
        rewardTracker.rewardPeriodStart = block.timestamp;

        emit RewardDistributionUpdated(
            rewardTracker.rewardPeriodStart,
            rewardTracker.rewardPeriodEnd,
            rewardTracker.rewardAmount
        );
    }

    /**
     * @return {qAsset}
     */
    function totalAssets() public view override returns (uint256) {
        // {qAsset} = {qAsset} + {qAsset}
        return totalDeposited + _currentAccountedRewards();
    }

    function addRewards(uint256 _amount) external {
        IERC20 _asset = IERC20(asset());

        if (_amount != 0) {
            SafeERC20.safeTransferFrom(_asset, msg.sender, address(this), _amount);
        }

        _updateRewards();
    }

    /**
     * @return {qAsset}
     */
    function _currentAccountedRewards() internal view returns (uint256) {
        if (block.timestamp >= rewardTracker.rewardPeriodEnd) {
            return rewardTracker.rewardAmount;
        }

        uint256 previousDistributionPeriod = rewardTracker.rewardPeriodEnd - rewardTracker.rewardPeriodStart;
        uint256 timePassed = block.timestamp - rewardTracker.rewardPeriodStart;

        // {qAsset} = {qAsset} * {s} / {s}
        return (rewardTracker.rewardAmount * timePassed) / previousDistributionPeriod;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _updateRewards();

        super._deposit(caller, receiver, assets, shares);
        totalDeposited += assets;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        _updateRewards();

        super._withdraw(caller, receiver, owner, assets, shares);
        totalDeposited -= assets;
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }
}
