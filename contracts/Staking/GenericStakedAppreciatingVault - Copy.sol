// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626, IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

uint256 constant SCALING_FACTOR = 1e18;

contract GenericStakedAppreciatingVault2 is ERC4626 {
    uint256 public immutable REWARDS_DURATION;

    /**
     * @notice Timestamp when the current rewards period will end.
     */
    uint256 public periodFinish;

    /**
     * @notice Rate at which rewards are distributed per second.
     */
    uint256 public rewardRate;

    /**
     * @notice Timestamp of the last update to the reward variables.
     */
    uint256 public lastUpdateTime;

    /**
     * @notice Accumulated reward per token stored.
     */
    uint256 public rewardPerTokenStored;

    /**
     * @notice Last calculated reward per token paid to stakers.
     */
    uint256 public rewardPerTokenPaid;

    /**
     * @notice Total rewards available for distribution.
     */
    uint256 public rewards;

    /**
     * @notice Total assets actively staked in the vault.
     */
    uint256 public totalStaked;

    error NoRewards();

    event RewardAdded(uint256 reward, uint256 periodStart, uint256 periodEnd);

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying,
        uint256 _distributionPeriod // {s} Distribution Period for Accumulated Rewards
    ) ERC4626(_underlying) ERC20(_name, _symbol) {
        REWARDS_DURATION = _distributionPeriod;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function earned() public view returns (uint256) {
        return ((totalStaked * (rewardPerToken() - rewardPerTokenPaid)) / SCALING_FACTOR) + rewards;
    }

    modifier updateReward(bool updateEarned) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (updateEarned) {
            rewards = earned();
            rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 _rewards = ((totalStaked * (rewardPerToken() - rewardPerTokenPaid)) / SCALING_FACTOR) + rewards;

        return totalStaked + _rewards;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            ((((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate) * SCALING_FACTOR) / totalStaked);
    }

    function accountRewards(uint256 _amount) public updateReward(false) {
        IERC20 _asset = IERC20(asset());

        if (_amount != 0) {
            SafeERC20.safeTransferFrom(_asset, msg.sender, address(this), _amount);
        }

        uint256 rewardBalance = _asset.balanceOf(address(this)) - totalStaked - earned();
        rewardRate = rewardBalance / REWARDS_DURATION;

        if (rewardRate == 0) {
            revert NoRewards();
        }

        lastUpdateTime = block.timestamp + 1;
        periodFinish = lastUpdateTime + REWARDS_DURATION;

        emit RewardAdded(rewardBalance, lastUpdateTime, periodFinish);
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override updateReward(true) {
        super._deposit(caller, receiver, assets, shares);

        totalStaked += assets;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override updateReward(true) {
        if (assets > totalStaked) {
            if (rewards != 0) {
                totalStaked += rewards;
            }
        }

        super._withdraw(caller, receiver, owner, assets, shares);

        totalStaked -= assets;
    }

    function assetsPerShare() external view returns (uint256) {
        return previewRedeem(1e18);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 0; // TODO: Change this?
    }
}
