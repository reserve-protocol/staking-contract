// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626, IERC20, IERC20Metadata, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { RewardInfo, Errors, Events, SCALAR } from "./definitions.sol";

/**
 * @title GenericMultiRewardsVault
 * @notice Non-transferrable ERC4626 vault that allows streaming of rewards in multiple other tokens
 * @dev Reward tokens transferred by accident without using `fundReward()` will be lost!
 *      Registering new reward tokens is permissioned, but adding funds is permissionless.
 *      No appreciation; exchange rate is always 1:1 with underlying.

 * Unit notation
 *   - {qRewardTok} = Reward token quanta
 *   - {qAsset} = Asset token quanta
 *   - {qShare} = Share token quanta
 *   - {s} = Seconds
 */
contract GenericMultiRewardsVault is ERC4626, Ownable {
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying,
        address initialOwner
    ) ERC4626(_underlying) ERC20(_name, _symbol) Ownable(initialOwner) {}

    /**
     * Core Vault Functionality
     */
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    function _convertToShares(uint256 assets, Math.Rounding) internal pure override returns (uint256) {
        return assets;
    }

    function _convertToAssets(uint256 shares, Math.Rounding) internal pure override returns (uint256) {
        return shares;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override accrueRewards(caller, receiver) {
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner_,
        uint256 assets,
        uint256 shares
    ) internal override accrueRewards(owner_, receiver) {
        super._withdraw(caller, receiver, owner_, assets, shares);
    }

    /**
     * @dev Prevent transfer
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert Errors.NotAllowed();
        }

        super._update(from, to, amount);
    }

    /**
     * Rewards: Claim Logic
     */

    /**
     * @notice Claim rewards for a user in any amount of rewardTokens.
     * @param user User for which rewards should be claimed.
     * @param _rewardTokens Array of rewardTokens for which rewards should be claimed.
     * @dev This function will revert if any of the rewardTokens have zero rewards accrued.
     */
    function claimRewards(address user, IERC20[] memory _rewardTokens) external accrueRewards(msg.sender, user) {
        for (uint8 i; i < _rewardTokens.length; i++) {
            uint256 rewardAmount = accruedRewards[user][_rewardTokens[i]];

            if (rewardAmount == 0) {
                continue;
            }

            accruedRewards[user][_rewardTokens[i]] = 0;
            SafeERC20.safeTransfer(_rewardTokens[i], user, rewardAmount);

            emit Events.RewardsClaimed(user, _rewardTokens[i], rewardAmount);
        }
    }

    /**
     * Rewards: Management
     */
    IERC20[] public rewardTokens;
    mapping(IERC20 rewardToken => RewardInfo rewardInfo) public rewardInfos;
    mapping(IERC20 rewardToken => address distributor) public distributorInfo;

    mapping(address user => mapping(IERC20 rewardToken => uint256 rewardIndex)) public userIndex; // {qRewardTok}
    mapping(address user => mapping(IERC20 rewardToken => uint256 accruedRewards)) public accruedRewards; // {qRewardTok}

    /**
     * @notice Adds a new rewardToken which can be earned via staking. Caller must be owner.
     * @param rewardToken Token that can be earned by staking.
     * @param distributor Distributor with the ability to control rewards for this token.
     * @param rewardsPerSecond {qRewardTok/s} The rate in which `rewardToken` will be accrued.
     * @param amount {qRewardTok} Initial funding amount for this reward.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly. In this case `amount` must be 0.
     *      This is useful for dynamic rewards, where the rewards are controlled by an external contract.
     */
    function addRewardToken(
        IERC20Metadata rewardToken,
        address distributor,
        uint256 rewardsPerSecond,
        uint256 amount
    ) external onlyOwner {
        if (asset() == address(rewardToken)) {
            revert Errors.RewardTokenCanNotBeStakingToken();
        }

        RewardInfo memory rewards = rewardInfos[rewardToken];
        if (rewards.lastUpdatedTimestamp > 0) {
            revert Errors.RewardTokenAlreadyExist(rewardToken);
        }

        if (amount != 0) {
            if (rewardsPerSecond == 0) {
                revert Errors.ZeroRewardsSpeed();
            }

            SafeERC20.safeTransferFrom(rewardToken, msg.sender, address(this), amount);
        }

        rewardTokens.push(rewardToken);

        uint8 rewardTokenDecimals = rewardToken.decimals();

        uint256 ONE = 10 ** rewardTokenDecimals;
        uint48 rewardsEndTimestamp = rewardsPerSecond == 0
            ? SafeCast.toUint48(block.timestamp)
            : _calcRewardsEnd(0, rewardsPerSecond, amount);

        rewardInfos[rewardToken] = RewardInfo({
            decimals: rewardTokenDecimals,
            rewardsEndTimestamp: rewardsEndTimestamp,
            lastUpdatedTimestamp: SafeCast.toUint48(block.timestamp),
            rewardsPerSecond: rewardsPerSecond,
            index: ONE * SCALAR,
            ONE: ONE
        });
        distributorInfo[rewardToken] = distributor;

        emit Events.RewardInfoUpdate(rewardToken, rewardsPerSecond, rewardsEndTimestamp);
    }

    /**
     * @notice Updates distributor for `rewardToken`
     * @param rewardToken Token that can be earned by staking.
     * @param distributor Distributor with the ability to control rewards for this token.
     * @dev Callable by owner or distributor themselves.
     * @dev Setting to address(0) will only allow owner to control it.
     */
    function updateDistributor(IERC20 rewardToken, address distributor) external {
        if (_msgSender() != owner() && _msgSender() != distributorInfo[rewardToken]) {
            revert Errors.InvalidCaller(_msgSender());
        }

        distributorInfo[rewardToken] = distributor;
    }

    /**
     * @notice Changes `rewardsPerSecond` for rewardToken.
     * @param rewardToken Token that can be earned by staking.
     * @param rewardsPerSecond The rate in which `rewardToken` will be accrued.
     * @dev Callable by owner or distributor for the token.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev Only for rewards that accrue over time.
     */
    function changeRewardSpeed(IERC20 rewardToken, uint256 rewardsPerSecond) external {
        if (_msgSender() != owner() && _msgSender() != distributorInfo[rewardToken]) {
            revert Errors.InvalidCaller(_msgSender());
        }

        RewardInfo memory rewards = rewardInfos[rewardToken];

        if (rewardsPerSecond == 0) {
            revert Errors.ZeroAmount();
        }
        if (rewards.lastUpdatedTimestamp == 0) {
            revert Errors.RewardTokenDoesNotExist(rewardToken);
        }
        if (rewards.rewardsPerSecond == 0) {
            revert Errors.RewardsAreDynamic(rewardToken);
        }

        _accrueRewards(rewardToken, _accrueStatic(rewards));

        uint256 prevEndTime = uint256(rewards.rewardsEndTimestamp);
        uint256 remainder = prevEndTime <= block.timestamp
            ? 0
            : uint256(rewards.rewardsPerSecond) * (prevEndTime - block.timestamp);
        uint48 rewardsEndTimestamp = _calcRewardsEnd(SafeCast.toUint48(block.timestamp), rewardsPerSecond, remainder);

        rewardInfos[rewardToken].rewardsPerSecond = rewardsPerSecond;
        rewardInfos[rewardToken].rewardsEndTimestamp = rewardsEndTimestamp;
    }

    /**
     * @notice Fund reward streams for a rewardToken.
     * @param rewardToken Token that can be earned by staking.
     * @param amount The amount of rewardToken that will fund this reward.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly.
     * @dev Permissionless
     */
    function fundReward(IERC20 rewardToken, uint256 amount) external {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        RewardInfo memory rewards = rewardInfos[rewardToken];

        if (rewards.rewardsPerSecond == 0 && totalSupply() == 0) {
            revert Errors.InvalidConfig();
        }

        if (rewards.lastUpdatedTimestamp == 0) {
            revert Errors.RewardTokenDoesNotExist(rewardToken);
        }

        SafeERC20.safeTransferFrom(rewardToken, msg.sender, address(this), amount);

        _accrueRewards(rewardToken, rewards.rewardsPerSecond == 0 ? amount : _accrueStatic(rewards));

        uint48 rewardsEndTimestamp = rewards.rewardsEndTimestamp;
        if (rewards.rewardsPerSecond > 0) {
            rewardsEndTimestamp = _calcRewardsEnd(rewards.rewardsEndTimestamp, rewards.rewardsPerSecond, amount);
            rewardInfos[rewardToken].rewardsEndTimestamp = rewardsEndTimestamp;
        }

        emit Events.RewardInfoUpdate(rewardToken, rewards.rewardsPerSecond, rewardsEndTimestamp);
    }

    /**
     * @param rewardsEndTimestamp {s}
     * @param rewardsPerSecond {qRewardTok/s}
     * @param amount {qRewardTok}
     * @return {s}
     */
    function _calcRewardsEnd(
        uint48 rewardsEndTimestamp,
        uint256 rewardsPerSecond,
        uint256 amount
    ) internal view returns (uint48) {
        if (rewardsEndTimestamp > block.timestamp) {
            // {qRewardTok} += ({qRewardTok/s} * ({s} - {s}))
            amount += rewardsPerSecond * (rewardsEndTimestamp - block.timestamp);
        }

        // {s} = {s} + ({qRewardTok} / {qRewardTok/s})
        return SafeCast.toUint48(block.timestamp + (amount / uint256(rewardsPerSecond)));
    }

    function getAllRewardsTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

    modifier accrueRewards(address _caller, address _receiver) {
        IERC20[] memory _rewardTokens = rewardTokens;
        for (uint256 i; i < _rewardTokens.length; i++) {
            IERC20 rewardToken = _rewardTokens[i];
            RewardInfo memory rewards = rewardInfos[rewardToken];

            if (rewards.rewardsPerSecond != 0) {
                _accrueRewards(rewardToken, _accrueStatic(rewards));
            }

            _accrueUser(_receiver, rewardToken);

            // If a deposit/withdraw operation gets called for another user we should
            // accrue for both of them to avoid potential issues
            if (_receiver != _caller) {
                _accrueUser(_caller, rewardToken);
            }
        }
        _;
    }

    /**
     * @notice Accrue rewards over time.
     * @return accrued {qRewardTok}
     */
    function _accrueStatic(RewardInfo memory rewards) internal view returns (uint256 accrued) {
        uint256 elapsed;
        if (rewards.rewardsEndTimestamp > block.timestamp) {
            elapsed = block.timestamp - rewards.lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > rewards.lastUpdatedTimestamp) {
            elapsed = rewards.rewardsEndTimestamp - rewards.lastUpdatedTimestamp;
        }

        // {qRewardTok} = {qRewardTok/s} * {s}
        accrued = uint256(rewards.rewardsPerSecond * elapsed);
    }

    /**
     * @notice Accrue global rewards for a rewardToken
     * @param accrued {qRewardTok}
     */
    function _accrueRewards(IERC20 _rewardToken, uint256 accrued) internal {
        uint256 supplyTokens = totalSupply();
        uint256 deltaIndex;

        if (supplyTokens != 0) {
            // {qRewardTok} = {qRewardTok} * {qShare} / {qShare}
            deltaIndex = (accrued * uint256(10 ** decimals()) * SCALAR) / supplyTokens;
        }

        // {qRewardTok} += {qRewardTok}
        rewardInfos[_rewardToken].index += deltaIndex;
        rewardInfos[_rewardToken].lastUpdatedTimestamp = SafeCast.toUint48(block.timestamp);
    }

    /**
     * @notice Sync a user's rewards for a rewardToken with the global reward index for that token
     */
    function _accrueUser(address _user, IERC20 _rewardToken) internal {
        RewardInfo memory rewardIndex = rewardInfos[_rewardToken];

        uint256 oldIndex = userIndex[_user][_rewardToken];

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (oldIndex == 0) {
            oldIndex = rewardIndex.ONE * SCALAR;
        }

        uint256 deltaIndex = rewardIndex.index - oldIndex;

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        // {qRewardTok} = {qShare} * {qRewardTok} / {qShare}
        uint256 supplierDelta = (balanceOf(_user) * deltaIndex) / uint256(10 ** decimals()) / SCALAR;

        // {qRewardTok} += {qRewardTok}
        accruedRewards[_user][_rewardToken] += supplierDelta;
        userIndex[_user][_rewardToken] = rewardIndex.index;
    }
}
