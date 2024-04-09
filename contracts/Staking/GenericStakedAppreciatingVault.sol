// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626, IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

uint256 constant SCALING_FACTOR = 1e18;

contract GenericStakedAppreciatingVault is ERC4626 {
    struct RewardTracker {
        uint256 rewardPeriodStart;
        uint256 rewardPeriodEnd;
        uint256 rewardAmount;
    }

    uint256 public immutable DISTRIBUTION_PERIOD;

    RewardTracker public rewardTracker;
    uint256 private totalDeposited;

    event RewardAdded(uint256 reward, uint256 periodStart, uint256 periodEnd);

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying,
        uint256 _distributionPeriod // {s} Distribution Period for Accumulated Rewards
    ) ERC4626(_underlying) ERC20(_name, _symbol) {
        DISTRIBUTION_PERIOD = _distributionPeriod;
    }

    function _updateRewards(bool useFullDuration) internal {
        IERC20 _asset = IERC20(asset());

        totalDeposited = totalAssets();

        uint256 allAvailableAssets = _asset.balanceOf(address(this));
        uint256 rewardsToBeDistributed = allAvailableAssets - totalDeposited;

        if (rewardsToBeDistributed != 0) {
            if (useFullDuration) {
                rewardTracker.rewardPeriodEnd = block.timestamp + DISTRIBUTION_PERIOD;
            }

            rewardTracker.rewardAmount = rewardsToBeDistributed;
            rewardTracker.rewardPeriodStart = block.timestamp;
        }
    }

    function totalAssets() public view override returns (uint256) {
        if (block.timestamp >= rewardTracker.rewardPeriodEnd) {
            return totalDeposited + rewardTracker.rewardAmount;
        }

        uint256 previousDistributionPeriod = rewardTracker.rewardPeriodEnd - rewardTracker.rewardPeriodStart;
        uint256 timePassed = block.timestamp - rewardTracker.rewardPeriodStart;
        uint256 timePassedPercentage = (timePassed * SCALING_FACTOR) / previousDistributionPeriod;

        uint256 accountedRewards = (rewardTracker.rewardAmount * timePassedPercentage) / SCALING_FACTOR;

        return totalDeposited + accountedRewards;
    }

    function addRewards(uint256 _amount) public {
        IERC20 _asset = IERC20(asset());

        if (_amount != 0) {
            SafeERC20.safeTransferFrom(_asset, msg.sender, address(this), _amount);
        }

        _updateRewards(true);

        emit RewardAdded(rewardTracker.rewardAmount, rewardTracker.rewardPeriodStart, rewardTracker.rewardPeriodEnd);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _updateRewards(false); // Does not change distribution timeline

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
        _updateRewards(false); // Does not change distribution timeline

        super._withdraw(caller, receiver, owner, assets, shares);
        totalDeposited -= assets;
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 0; // TODO: Change this?
    }
}
