// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

struct RewardInfo {
    uint8 decimals; // Reward Token Decimals
    uint48 rewardsEndTimestamp; // {s} Rewards End Timestamp; 0 = instant
    uint48 lastUpdatedTimestamp; // {s} Last updated timestamp
    uint256 rewardsPerSecond; // {qRewardTok/s} Rewards per Second
    uint256 index; // {qRewardTok} Last updated reward index
    uint256 ONE; // {qRewardTok} Reward Token Scalar
}

abstract contract Errors {
    // Reward Claiming
    error ZeroRewards(IERC20 rewardToken);

    // Reward Management
    error RewardTokenAlreadyExist(IERC20 rewardToken);
    error RewardTokenDoesNotExist(IERC20 rewardToken);
    error RewardTokenCanNotBeStakingToken();
    error ZeroAmount();
    error NotSubmitter(address submitter);
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
