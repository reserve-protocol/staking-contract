// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626, IERC20, IERC20Metadata, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { RewardInfo, Errors, Events } from "./definitions.sol";

contract GenericMultiRewardsVault is ERC4626, Ownable {
    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _underlying,
        address initialOwner
    ) ERC4626(_underlying) ERC20(_name, _symbol) Ownable(initialOwner) {}

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

    error NotAllowed();

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert NotAllowed();
        }

        super._update(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

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
                revert Errors.ZeroRewards(_rewardTokens[i]);
            }

            accruedRewards[user][_rewardTokens[i]] = 0;
            _rewardTokens[i].transfer(user, rewardAmount);

            emit Events.RewardsClaimed(user, _rewardTokens[i], rewardAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    REWARDS MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    IERC20[] public rewardTokens;
    mapping(IERC20 rewardToken => RewardInfo rewardInfo) public rewardInfos;

    mapping(address user => mapping(IERC20 rewardToken => uint256 rewardIndex)) public userIndex;
    mapping(address user => mapping(IERC20 rewardToken => uint256 accruedRewards)) public accruedRewards;

    /**
     * @notice Adds a new rewardToken which can be earned via staking. Caller must be owner.
     * @param rewardToken Token that can be earned by staking.
     * @param rewardsPerSecond The rate in which `rewardToken` will be accrued.
     * @param amount Initial funding amount for this reward.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly. In this case `amount` must be 0.
     * @dev If `useEscrow` is `false` the `escrowDuration`, `escrowPercentage` and `offset` will be ignored.
     */
    function addRewardToken(IERC20Metadata rewardToken, uint256 rewardsPerSecond, uint256 amount) external onlyOwner {
        if (asset() == address(rewardToken)) {
            revert Errors.RewardTokenCanNotBeStakingToken();
        }

        RewardInfo memory rewards = rewardInfos[rewardToken];
        if (rewards.lastUpdatedTimestamp > 0) {
            revert Errors.RewardTokenAlreadyExist(rewardToken);
        }

        if (amount > 0) {
            if (rewardsPerSecond == 0) {
                revert Errors.ZeroRewardsSpeed();
            }

            SafeERC20.safeTransferFrom(rewardToken, msg.sender, address(this), amount);
        }

        rewardTokens.push(rewardToken);

        uint8 rewardTokenDecimals = rewardToken.decimals();

        uint256 ONE = 10 ** rewardTokenDecimals;
        uint256 index = rewardsPerSecond == 0 && amount != 0
            ? ONE + ((amount * uint256(10 ** decimals())) / totalSupply())
            : ONE;
        uint48 rewardsEndTimestamp = rewardsPerSecond == 0
            ? SafeCast.toUint48(block.timestamp)
            : _calcRewardsEnd(0, rewardsPerSecond, amount);

        rewardInfos[rewardToken] = RewardInfo({
            decimals: rewardTokenDecimals,
            rewardsEndTimestamp: rewardsEndTimestamp,
            lastUpdatedTimestamp: SafeCast.toUint48(block.timestamp),
            rewardsPerSecond: rewardsPerSecond,
            index: index,
            ONE: ONE
        });

        emit Events.RewardInfoUpdate(rewardToken, rewardsPerSecond, rewardsEndTimestamp);
    }

    /**
     * @notice Changes rewards speed for a rewardToken. This works only for rewards that accrue over time. Caller must be owner.
     * @param rewardToken Token that can be earned by staking.
     * @param rewardsPerSecond The rate in which `rewardToken` will be accrued.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     */
    function changeRewardSpeed(IERC20 rewardToken, uint256 rewardsPerSecond) external onlyOwner {
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
     * @notice Funds rewards for a rewardToken.
     * @param rewardToken Token that can be earned by staking.
     * @param amount The amount of rewardToken that will fund this reward.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly.
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

    function _calcRewardsEnd(
        uint48 rewardsEndTimestamp,
        uint256 rewardsPerSecond,
        uint256 amount
    ) internal view returns (uint48) {
        if (rewardsEndTimestamp > block.timestamp) {
            amount += rewardsPerSecond * (rewardsEndTimestamp - block.timestamp);
        }

        return SafeCast.toUint48(block.timestamp + (amount / uint256(rewardsPerSecond)));
    }

    function getAllRewardsTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                      REWARDS ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Accrue rewards for up to 2 users for all available reward tokens.
    modifier accrueRewards(address _caller, address _receiver) {
        IERC20[] memory _rewardTokens = rewardTokens;
        for (uint256 i; i < _rewardTokens.length; i++) {
            IERC20 rewardToken = _rewardTokens[i];
            RewardInfo memory rewards = rewardInfos[rewardToken];

            if (rewards.rewardsPerSecond != 0) {
                _accrueRewards(rewardToken, _accrueStatic(rewards));
            }

            _accrueUser(_receiver, rewardToken);

            // If a deposit/withdraw operation gets called for another user we should accrue for both of them to avoid potential issues
            if (_receiver != _caller) {
                _accrueUser(_caller, rewardToken);
            }
        }
        _;
    }

    /**
     * @notice Accrue rewards over time.
     * @dev Based on https://github.com/fei-protocol/flywheel-v2/blob/main/src/rewards/FlywheelStaticRewards.sol
     */
    function _accrueStatic(RewardInfo memory rewards) internal view returns (uint256 accrued) {
        uint256 elapsed;
        if (rewards.rewardsEndTimestamp > block.timestamp) {
            elapsed = block.timestamp - rewards.lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > rewards.lastUpdatedTimestamp) {
            elapsed = rewards.rewardsEndTimestamp - rewards.lastUpdatedTimestamp;
        }

        accrued = uint256(rewards.rewardsPerSecond * elapsed);
    }

    /// @notice Accrue global rewards for a rewardToken
    function _accrueRewards(IERC20 _rewardToken, uint256 accrued) internal {
        uint256 supplyTokens = totalSupply();
        uint256 deltaIndex;

        if (supplyTokens != 0) {
            deltaIndex = (accrued * uint256(10 ** decimals())) / supplyTokens;
        }

        rewardInfos[_rewardToken].index += deltaIndex;
        rewardInfos[_rewardToken].lastUpdatedTimestamp = SafeCast.toUint48(block.timestamp);
    }

    /// @notice Sync a user's rewards for a rewardToken with the global reward index for that token
    function _accrueUser(address _user, IERC20 _rewardToken) internal {
        RewardInfo memory rewardIndex = rewardInfos[_rewardToken];

        uint256 oldIndex = userIndex[_user][_rewardToken];

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (oldIndex == 0) {
            oldIndex = rewardIndex.ONE;
        }

        uint256 deltaIndex = rewardIndex.index - oldIndex;

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (balanceOf(_user) * deltaIndex) / uint256(10 ** decimals());
        // stakeDecimals  * rewardDecimals / stakeDecimals = rewardDecimals

        userIndex[_user][_rewardToken] = rewardIndex.index;
        accruedRewards[_user][_rewardToken] += supplierDelta;
    }
}
