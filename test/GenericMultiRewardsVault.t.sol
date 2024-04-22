// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20Mock } from "@test/mocks/ERC20Mock.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { GenericMultiRewardsVault, IERC20, IERC20Metadata } from "@src/rewards/GenericMultiRewardsVault.sol";
import { Errors, Events } from "@src/rewards/Definitions.sol";

// Test Suite based on Popcorn DAO's MultiRewardStaking
// See: https://github.com/Popcorn-Limited/contracts/blob/d029c413239735f58b0adcead11fdbe8f69a0e34/test/MultiRewardStaking.t.sol
// Modified to work in this context.
contract GenericMultiRewardsVaultTest is Test {
    ERC20Mock stakingToken;
    ERC20Mock rewardToken1;
    ERC20Mock rewardToken2;

    IERC20 iRewardToken1;
    IERC20 iRewardToken2;
    GenericMultiRewardsVault staking;

    address alice = address(0xA);
    address bob = address(0xB);

    function setUp() public {
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        stakingToken = new ERC20Mock("Testing Token", "TEST", 18);

        rewardToken1 = new ERC20Mock("RewardsToken1", "RTKN1", 18);
        rewardToken2 = new ERC20Mock("RewardsToken2", "RTKN2", 6);

        vm.label(address(rewardToken1), "RewardToken1");
        vm.label(address(rewardToken2), "RewardToken2");

        iRewardToken1 = IERC20(address(rewardToken1));
        iRewardToken2 = IERC20(address(rewardToken2));

        staking = new GenericMultiRewardsVault(
            "Staked Testing Token",
            "sTEST",
            IERC20(address(stakingToken)),
            address(this)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__metaData() public view {
        assertEq(staking.name(), "Staked Testing Token");
        assertEq(staking.symbol(), "sTEST");
        assertEq(staking.decimals(), stakingToken.decimals());
    }

    function test__getAllRewardsTokens() public {
        _addRewardToken(rewardToken1);
        IERC20[] memory rewardTokens = staking.getAllRewardsTokens();

        assertEq(rewardTokens.length, 1);
        assertEq(address(rewardTokens[0]), address(rewardToken1));
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__single_deposit_withdraw(uint128 amount) public {
        if (amount == 0) amount = 1;

        uint256 aliceUnderlyingAmount = amount;

        stakingToken.mint(alice, aliceUnderlyingAmount);

        vm.prank(alice);
        stakingToken.approve(address(staking), aliceUnderlyingAmount);
        assertEq(stakingToken.allowance(alice, address(staking)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = stakingToken.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = staking.deposit(aliceUnderlyingAmount, alice);

        // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(staking.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(staking.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(staking.totalSupply(), aliceShareAmount);
        assertEq(staking.totalAssets(), aliceUnderlyingAmount);
        assertEq(staking.balanceOf(alice), aliceShareAmount);
        assertEq(staking.convertToAssets(staking.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(stakingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        staking.withdraw(aliceUnderlyingAmount, alice, alice);

        assertEq(staking.totalAssets(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.convertToAssets(staking.balanceOf(alice)), 0);
        assertEq(stakingToken.balanceOf(alice), alicePreDepositBal);
    }

    function test__deposit_zero() public {
        staking.deposit(0, address(this));
        assertEq(staking.balanceOf(address(this)), 0);
    }

    function test__withdraw_zero() public {
        staking.withdraw(0, address(this), address(this));
    }

    function testFail__deposit_with_no_approval() public {
        staking.deposit(1e18, address(this));
    }

    function testFail__deposit_with_not_enough_approval() public {
        stakingToken.mint(address(this), 0.5e18);
        stakingToken.approve(address(staking), 0.5e18);
        assertEq(stakingToken.allowance(address(this), address(staking)), 0.5e18);

        staking.deposit(1e18, address(this));
    }

    function testFail__withdraw_with_not_enough_underlying_amount() public {
        stakingToken.mint(address(this), 0.5e18);
        stakingToken.approve(address(staking), 0.5e18);

        staking.deposit(0.5e18, address(this));

        staking.withdraw(1e18, address(this), address(this));
    }

    function testFail__withdraw_with_no_underlying_amount() public {
        staking.withdraw(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                         MINT/REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__single_mint_redeem(uint128 amount) public {
        if (amount == 0) amount = 1;

        uint256 aliceShareAmount = amount;

        stakingToken.mint(alice, aliceShareAmount);

        vm.prank(alice);
        stakingToken.approve(address(staking), aliceShareAmount);
        assertEq(stakingToken.allowance(alice, address(staking)), aliceShareAmount);

        uint256 alicePreDepositBal = stakingToken.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceUnderlyingAmount = staking.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(staking.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(staking.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(staking.totalSupply(), aliceShareAmount);
        assertEq(staking.totalAssets(), aliceUnderlyingAmount);
        assertEq(staking.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(staking.convertToAssets(staking.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(stakingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        staking.redeem(aliceShareAmount, alice, alice);

        assertEq(staking.totalAssets(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.convertToAssets(staking.balanceOf(alice)), 0);
        assertEq(stakingToken.balanceOf(alice), alicePreDepositBal);
    }

    function test__mint_zero() public {
        staking.mint(0, address(this));
        assertEq(staking.balanceOf(address(this)), 0);
    }

    function test__redeem_zero() public {
        staking.redeem(0, address(this), address(this));
    }

    function testFail__mint_with_no_approval() public {
        staking.mint(1e18, address(this));
    }

    function testFail__redeem_with_not_enough_share_amount() public {
        stakingToken.mint(address(this), 0.5e18);
        stakingToken.approve(address(staking), 0.5e18);

        staking.deposit(0.5e18, address(this));

        staking.redeem(1e18, address(this), address(this));
    }

    function testFail__redeem_with_no_share_amount() public {
        staking.redeem(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__accrual_singleToken() public {
        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 5 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 5 ether);
        staking.deposit(1 ether);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);

        uint256 callTimestamp = block.timestamp;
        staking.deposit(1 ether);

        (, , uint48 lastUpdatedTimestamp, , uint256 index, uint256 ONE) = staking.rewardInfos(iRewardToken1);
        // console2.log(index);
        // console2.log("ts", staking.totalSupply());
        assertEq(uint256(index), 2 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        // Should be 1 ether of rewards
        assertEq(staking.accruedRewards(alice, iRewardToken1), 1 * ONE);

        // 20% of rewards paid out
        vm.warp(block.timestamp + 10);

        callTimestamp = block.timestamp;
        staking.mint(2 ether);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), (25 * ONE) / 10);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 2 * ONE);

        // 90% of rewards paid out
        vm.warp(block.timestamp + 70);

        callTimestamp = block.timestamp;
        staking.withdraw(2 ether);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), (425 * ONE) / 100);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 9 * ONE);

        // 100% of rewards paid out
        vm.warp(block.timestamp + 10);

        callTimestamp = block.timestamp;
        staking.redeem(1 ether);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), (475 * ONE) / 100);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 10 * ONE);
    }

    function test__accrual_multiple_rewardsToken() public {
        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 5 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 5 ether);
        staking.deposit(1 ether);

        vm.warp(block.timestamp + 10);

        uint256 callTimestamp = block.timestamp;
        staking.deposit(1 ether);

        // RewardsToken 1 -- 10% accrued
        (, , uint48 lastUpdatedTimestampReward1, , uint256 indexReward1, uint256 reward1ONE) = staking.rewardInfos(
            iRewardToken1
        );
        assertEq(uint256(indexReward1), 2 * reward1ONE);
        assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 1 * reward1ONE);

        // Add new rewardsToken
        vm.stopPrank();
        _addRewardToken(rewardToken2);
        vm.startPrank(alice);

        vm.warp(block.timestamp + 10);

        callTimestamp = block.timestamp;
        staking.deposit(2 ether);

        // RewardsToken 1 -- 20% accrued
        (, , lastUpdatedTimestampReward1, , indexReward1, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(indexReward1), (25 * reward1ONE) / 10);
        assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 2 * reward1ONE);

        // RewardsToken 2 -- 10% accrued
        (, , uint48 lastUpdatedTimestampReward2, , uint256 indexReward2, uint256 reward2ONE) = staking.rewardInfos(
            iRewardToken2
        );
        assertEq(uint256(indexReward2), (15 * reward2ONE) / 10);
        assertEq(uint256(lastUpdatedTimestampReward2), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken2), indexReward2);
        assertEq(staking.accruedRewards(alice, iRewardToken2), 1 * reward2ONE);

        vm.warp(block.timestamp + 80);

        callTimestamp = block.timestamp;
        staking.deposit(1 ether);

        // RewardsToken 1 -- 100% accrued
        (, , lastUpdatedTimestampReward1, , indexReward1, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(indexReward1), (45 * reward1ONE) / 10);
        assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 10 * reward1ONE);

        // RewardsToken 2 -- 90% accrued
        (, , lastUpdatedTimestampReward2, , indexReward2, ) = staking.rewardInfos(iRewardToken2);
        assertEq(uint256(indexReward2), (35 * reward2ONE) / 10);
        assertEq(uint256(lastUpdatedTimestampReward2), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken2), indexReward2);
        assertEq(staking.accruedRewards(alice, iRewardToken2), 9 * reward2ONE);
    }

    function test__accrual_on_claim() public {
        // Prepare array for `claimRewards`
        IERC20[] memory rewardsTokenKeys = new IERC20[](1);
        rewardsTokenKeys[0] = iRewardToken1;

        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 5 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 5 ether);
        staking.deposit(1 ether);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);

        uint256 callTimestamp = block.timestamp;
        staking.claimRewards(alice, rewardsTokenKeys);

        (, , uint48 lastUpdatedTimestamp, , uint256 index, uint256 ONE) = staking.rewardInfos(iRewardToken1);
        assertEq(rewardToken1.balanceOf(alice), 1 * ONE);

        assertEq(uint256(index), 2 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
    }

    function test__no_accrual_after_end() public {
        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 2 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 2 ether);
        staking.deposit(1 ether);
        vm.stopPrank();

        // 100% of rewards paid out
        vm.warp(block.timestamp + 100);

        uint256 callTimestamp = block.timestamp;
        vm.prank(alice);
        staking.deposit(1 ether);

        (, , uint48 lastUpdatedTimestamp, , uint256 index, uint256 ONE) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), 11 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 10 * ONE);

        // no more rewards after end time
        vm.warp(block.timestamp + 10);

        callTimestamp = block.timestamp;
        vm.prank(alice);
        staking.withdraw(1 ether);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), 11 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        // Alice didnt accumulate more rewards since we are past the end of the rewards
        assertEq(staking.accruedRewards(alice, iRewardToken1), 10 * ONE);
    }

    function test__accrual_with_user_joining_later() public {
        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 5 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 5 ether);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);

        uint256 callTimestamp = block.timestamp;
        staking.deposit(1 ether);

        (, , uint48 lastUpdatedTimestamp, , uint256 index, uint256 ONE) = staking.rewardInfos(iRewardToken1);
        // Accrual doesnt start until someone deposits -- TODO does this change some of the rewardsEnd and rewardsSpeed assumptions?
        assertEq(uint256(index), 1 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 0);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);

        callTimestamp = block.timestamp;
        staking.mint(2 ether, bob);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), 2 * ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 1 * ONE);

        assertEq(staking.userIndex(bob, iRewardToken1), index);
        assertEq(staking.accruedRewards(bob, iRewardToken1), 0);

        // 80% of rewards paid out
        vm.warp(block.timestamp + 70);

        staking.withdraw((5 * ONE) / 10);
        vm.stopPrank();
        vm.prank(bob);
        callTimestamp = block.timestamp;
        staking.withdraw((5 * ONE) / 10);

        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), ONE + (ONE * 10) / 3);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), (ONE * 10) / 3);

        assertEq(staking.userIndex(bob, iRewardToken1), index);
        assertEq(staking.accruedRewards(bob, iRewardToken1), ONE + (ONE * 10) / 3 + ONE / 3);
        // Both accruals add up to 80% of rewards paid out
    }

    /*//////////////////////////////////////////////////////////////
                        ADD REWARDS TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _addRewardToken(ERC20Mock rewardsToken) internal {
        uint8 rewardTokenDecimals = rewardsToken.decimals();
        uint256 ONE = 10 ** rewardTokenDecimals;

        rewardsToken.mint(address(this), 10 * ONE);
        rewardsToken.approve(address(staking), 10 * ONE);

        uint256 totalAmount = 10 * ONE;
        uint256 rewardsPerSecond = totalAmount / 100; // so, duration = 100

        staking.addRewardToken(IERC20Metadata(address(rewardsToken)), rewardsPerSecond, totalAmount);
    }

    function _addRewardTokenWithZeroRewardsSpeed(ERC20Mock rewardsToken) internal {
        staking.addRewardToken(IERC20Metadata(address(rewardsToken)), 0, 0);
    }

    function test__addRewardToken() public {
        // Prepare to transfer reward tokens
        rewardToken1.mint(address(this), 10 ether);
        rewardToken1.approve(address(staking), 10 ether);

        uint256 callTimestamp = block.timestamp;
        vm.expectEmit(false, false, false, true, address(staking));

        emit Events.RewardInfoUpdate(iRewardToken1, 0.1 ether, SafeCast.toUint32(callTimestamp + 100));

        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);

        // Confirm that all data is set correctly
        IERC20[] memory rewardTokens = staking.getAllRewardsTokens();
        assertEq(rewardTokens.length, 1);
        assertEq(address(rewardTokens[0]), address(iRewardToken1));

        (
            uint8 decimals,
            uint48 rewardsEndTimestamp,
            uint48 lastUpdatedTimestamp,
            uint256 rewardsPerSecond,
            uint256 index,
            uint256 ONE
        ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(ONE), 10 ** decimals);
        assertEq(rewardsPerSecond, 0.1 ether);
        assertEq(uint256(rewardsEndTimestamp), callTimestamp + 100);
        assertEq(index, ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

        // Confirm token transfer
        assertEq(rewardToken1.balanceOf(address(this)), 0);
        assertEq(rewardToken1.balanceOf(address(staking)), 10 ether);
    }

    function test__addRewardToken_0_rewardsSpeed() public {
        uint256 callTimestamp = block.timestamp;
        vm.expectEmit(false, false, false, true, address(staking));
        emit Events.RewardInfoUpdate(iRewardToken1, 0, SafeCast.toUint32(callTimestamp));

        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0, 0);

        (
            uint8 decimals,
            uint48 rewardsEndTimestamp,
            uint48 lastUpdatedTimestamp,
            uint256 rewardsPerSecond,
            uint256 index,
            uint256 ONE
        ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(ONE), 10 ** decimals);
        assertEq(rewardsPerSecond, 0);
        assertEq(uint256(rewardsEndTimestamp), callTimestamp);
        assertEq(index, ONE);
        assertEq(uint256(lastUpdatedTimestamp), callTimestamp);
    }

    function test__addRewardToken_end_time_not_affected_by_other_transfers() public {
        // Prepare to transfer reward tokens
        rewardToken1.mint(address(this), 20 ether);
        rewardToken1.approve(address(staking), 10 ether);

        // transfer some token to staking beforehand
        rewardToken1.transfer(address(staking), 10 ether);

        uint256 callTimestamp = block.timestamp;
        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);

        // RewardsEndTimeStamp shouldnt be affected by previous token transfer
        (, uint48 rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(rewardsEndTimestamp), callTimestamp + 100);

        // Confirm token transfer
        assertEq(rewardToken1.balanceOf(address(this)), 0);
        assertEq(rewardToken1.balanceOf(address(staking)), 20 ether);
    }

    function testFail__addRewardToken_token_exists() public {
        // Prepare to transfer reward tokens
        rewardToken1.mint(address(this), 20 ether);
        rewardToken1.approve(address(staking), 20 ether);

        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);

        vm.expectRevert(Errors.RewardTokenAlreadyExist.selector);
        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);
    }

    function testFail__addRewardToken_rewardsToken_is_stakingToken() public {
        staking.addRewardToken(IERC20Metadata(address(stakingToken)), 0.1 ether, 10 ether);
    }

    function testFail__addRewardToken_0_rewardsSpeed_non_0_amount() public {
        // Prepare to transfer reward tokens
        rewardToken1.mint(address(this), 1 ether);
        rewardToken1.approve(address(staking), 1 ether);

        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0, 1 ether);
    }

    function testFail__addRewardToken_escrow_with_0_percentage() public {
        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);
    }

    function testFail__addRewardToken_escrow_with_more_than_100_percentage() public {
        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0.1 ether, 10 ether);
    }

    function testFail__addRewardToken_0_rewardsSpeed_amount_larger_0_and_0_shares() public {
        staking.addRewardToken(IERC20Metadata(address(iRewardToken1)), 0, 10);
    }

    /*//////////////////////////////////////////////////////////////
                        CHANGE REWARDS SPEED LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__changeRewardSpeed() public {
        _addRewardToken(rewardToken1);

        (, , , , , uint256 ONE) = staking.rewardInfos(iRewardToken1);

        stakingToken.mint(alice, 1 ether);
        stakingToken.mint(bob, 1 ether);

        vm.prank(alice);
        stakingToken.approve(address(staking), 1 ether);
        vm.prank(bob);
        stakingToken.approve(address(staking), 1 ether);

        vm.prank(alice);
        staking.deposit(1 ether);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);
        // Double Accrual (from original)
        staking.changeRewardSpeed(iRewardToken1, (2 * ONE) / 10);

        // 30% of rewards paid out
        vm.warp(block.timestamp + 10);
        // Half Accrual (from original)
        staking.changeRewardSpeed(iRewardToken1, (5 * ONE) / 100);
        vm.prank(bob);
        staking.deposit(1 ether);

        // 50% of rewards paid out
        vm.warp(block.timestamp + 40);

        vm.prank(alice);
        staking.withdraw(1 ether);

        // Check Alice RewardsState
        (, , uint48 lastUpdatedTimestamp, , uint256 index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), 5 * ONE);

        assertEq(staking.userIndex(alice, iRewardToken1), index);
        assertEq(staking.accruedRewards(alice, iRewardToken1), 4 * ONE);

        vm.prank(bob);
        staking.withdraw(1 ether);

        // Check Bobs RewardsState
        (, , lastUpdatedTimestamp, , index, ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(index), 5 * ONE);

        assertEq(staking.userIndex(bob, iRewardToken1), index);
        assertEq(staking.accruedRewards(bob, iRewardToken1), 1 * ONE);
    }

    function test__changeRewardSpeed2() public {
        _addRewardToken(rewardToken1);

        stakingToken.mint(alice, 1 ether);

        vm.prank(alice);
        stakingToken.approve(address(staking), 1 ether);
        vm.prank(alice);
        staking.deposit(1 ether);

        (, uint48 rewardsEndTimestamp, , , , uint256 ONE) = staking.rewardInfos(iRewardToken1);
        // StartTime 1, Rewards 10e18, RewardsPerSecond 0.1e18, RewardsEndTimeStamp 101
        assertEq(rewardsEndTimestamp, 101);

        staking.changeRewardSpeed(iRewardToken1, (5 * ONE) / 10);
        (, rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        // StartTime 1, Rewards 10e18, RewardsPerSecond 0.5e18, RewardsEndTimeStamp 21
        assertEq(rewardsEndTimestamp, 21);

        vm.warp(block.timestamp + 10);

        // 50% paid out, CallTime 11, Rewards 5e18, RewardsPerSecond 0.1e18, RewardsEndTimeStamp 61
        staking.changeRewardSpeed(iRewardToken1, (1 * ONE) / 10);
        (, rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        assertEq(rewardsEndTimestamp, 61);
    }

    function testFail__changeRewardSpeed_to_0() public {
        _addRewardToken(rewardToken1);
        staking.changeRewardSpeed(iRewardToken1, 0);
    }

    function testFail__changeRewardSpeed_from_0() public {
        _addRewardTokenWithZeroRewardsSpeed(rewardToken1);
        staking.changeRewardSpeed(iRewardToken1, 1);
    }

    function testFail__changeRewardSpeed_reward_doesnt_exist() public {
        staking.changeRewardSpeed(iRewardToken1, 1);
    }

    function testFail__changeRewardSpeed_nonOwner() public {
        _addRewardToken(rewardToken1);
        vm.prank(alice);
        staking.changeRewardSpeed(iRewardToken1, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FUND REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__fundReward() public {
        _addRewardToken(rewardToken1);
        (, uint48 oldRewardsEndTimestamp, , , , uint256 ONE) = staking.rewardInfos(iRewardToken1);

        rewardToken1.mint(address(this), 10 * ONE);
        rewardToken1.approve(address(staking), 10 * ONE);

        vm.expectEmit(false, false, false, true, address(staking));
        emit Events.RewardInfoUpdate(iRewardToken1, (1 * ONE) / 10, oldRewardsEndTimestamp + 100);

        staking.fundReward(iRewardToken1, 10 * ONE);

        // RewardsEndTimeStamp should take new token into account
        (, uint48 rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp) + 100);

        // Confirm token transfer
        assertEq(rewardToken1.balanceOf(address(this)), 0);
        assertEq(rewardToken1.balanceOf(address(staking)), 20 * ONE);
    }

    function test__fundReward_0_rewardsSpeed() public {
        _addRewardTokenWithZeroRewardsSpeed(rewardToken1);

        rewardToken1.mint(address(this), 10 ether);
        rewardToken1.approve(address(staking), 10 ether);

        stakingToken.mint(address(this), 1 ether);
        stakingToken.approve(address(staking), 1 ether);

        staking.deposit(1 ether);

        (, uint48 oldRewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);

        vm.expectEmit(false, false, false, true, address(staking));
        emit Events.RewardInfoUpdate(iRewardToken1, 0, oldRewardsEndTimestamp);

        staking.fundReward(iRewardToken1, 10 ether);

        // RewardsEndTimeStamp should take new token into account
        (, uint48 rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp));

        // Confirm token transfer
        assertEq(rewardToken1.balanceOf(address(this)), 0);
        assertEq(rewardToken1.balanceOf(address(staking)), 10 ether);
    }

    function test__fundReward_end_time_not_affected_by_other_transfers() public {
        // Prepare to transfer reward tokens
        _addRewardToken(rewardToken1);
        (, uint48 oldRewardsEndTimestamp, , , , uint256 ONE) = staking.rewardInfos(iRewardToken1);

        rewardToken1.mint(address(this), 20 * ONE);
        rewardToken1.approve(address(staking), 10 * ONE);

        // transfer some token to staking beforehand
        rewardToken1.transfer(address(staking), 10 * ONE);

        staking.fundReward(iRewardToken1, 10 * ONE);

        // RewardsEndTimeStamp shouldnt be affected by previous token transfer
        (, uint48 rewardsEndTimestamp, , , , ) = staking.rewardInfos(iRewardToken1);
        assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp) + 100);

        // Confirm token transfer
        assertEq(rewardToken1.balanceOf(address(this)), 0);
        assertEq(rewardToken1.balanceOf(address(staking)), 30 * ONE);
    }

    function testFail__fundReward_zero_amount() public {
        _addRewardToken(rewardToken1);

        staking.fundReward(iRewardToken1, 0);
    }

    function testFail__fundReward_no_rewardsToken() public {
        staking.fundReward(IERC20(address(0)), 10 ether);
    }

    function testFail__fundReward_0_rewardsSpeed_zero_shares() public {
        _addRewardTokenWithZeroRewardsSpeed(rewardToken1);

        rewardToken1.mint(address(this), 10 ether);
        rewardToken1.approve(address(staking), 10 ether);

        staking.fundReward(iRewardToken1, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__claim() public {
        // Prepare array for `claimRewards`
        IERC20[] memory rewardsTokenKeys = new IERC20[](1);
        rewardsTokenKeys[0] = iRewardToken1;

        _addRewardToken(rewardToken1);
        stakingToken.mint(alice, 5 ether);

        (, , , , , uint256 ONE) = staking.rewardInfos(iRewardToken1);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 5 ether);
        staking.deposit(1 ether);

        // 10% of rewards paid out
        vm.warp(block.timestamp + 10);

        vm.expectEmit(false, false, false, true, address(staking));
        emit Events.RewardsClaimed(alice, iRewardToken1, 1 * ONE);

        staking.claimRewards(alice, rewardsTokenKeys);

        assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
        assertEq(rewardToken1.balanceOf(alice), 1 * ONE);
    }

    function test__claim_0_rewardsSpeed() public {
        // Prepare array for `claimRewards`
        IERC20[] memory rewardsTokenKeys = new IERC20[](1);
        rewardsTokenKeys[0] = iRewardToken1;

        _addRewardTokenWithZeroRewardsSpeed(rewardToken1);
        rewardToken1.mint(address(this), 5 ether);
        rewardToken1.approve(address(staking), 5 ether);
        stakingToken.mint(alice, 1 ether);

        vm.startPrank(alice);
        stakingToken.approve(address(staking), 1 ether);
        staking.deposit(1 ether);
        vm.stopPrank();

        staking.fundReward(iRewardToken1, 5 ether);

        vm.expectEmit(false, false, false, true, address(staking));
        emit Events.RewardsClaimed(alice, iRewardToken1, 5 ether);

        staking.claimRewards(alice, rewardsTokenKeys);

        assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
        assertEq(rewardToken1.balanceOf(alice), 5 ether);
    }

    function testFail__claim_non_existent_rewardsToken() public {
        IERC20[] memory rewardsTokenKeys = new IERC20[](1);

        vm.prank(alice);
        staking.claimRewards(alice, rewardsTokenKeys);
    }

    function testFail__claim_non_existent_reward() public {
        IERC20[] memory rewardsTokenKeys = new IERC20[](1);

        vm.prank(alice);
        staking.claimRewards(alice, rewardsTokenKeys);
    }
}
