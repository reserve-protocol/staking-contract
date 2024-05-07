// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

uint256 constant SCALAR = 1e18;

struct RewardInfo {
    uint8 decimals; // Reward Token Decimals
    uint48 rewardsEndTimestamp; // {s} Rewards End Timestamp
    uint48 lastUpdatedTimestamp; // {s} Last updated timestamp
    uint256 rewardsPerSecond; // {qRewardTok/s} Rewards per Second; 0 = instant
    uint256 index; // {qRewardTok} Last updated reward index
    uint256 ONE; // {qRewardTok} Reward Token Scalar
}

abstract contract Errors {
    // Reward Management
    error InvalidRewardToken(IERC20 rewardToken);
    error RewardTokenAlreadyBlocked(IERC20 rewardToken);
    error RewardTokenAlreadyExist(IERC20 rewardToken);
    error RewardTokenDoesNotExist(IERC20 rewardToken);
    error RewardTokenCanNotBeStakingToken();
    error RewardTokenBlocked(IERC20 rewardToken);
    error ZeroAmount();
    error RewardsAreDynamic(IERC20 rewardToken);
    error ZeroRewardsSpeed();
    error InvalidConfig();
    error InvalidCaller(address caller);

    // Transfers
    error NotAllowed();
}

abstract contract Events {
    // Reward Claiming
    event RewardsClaimed(address indexed user, IERC20 rewardToken, uint256 amount);

    // Reward Management
    event RewardInfoUpdate(IERC20 rewardToken, uint256 rewardsPerSecond, uint48 rewardsEndTimestamp);
}
