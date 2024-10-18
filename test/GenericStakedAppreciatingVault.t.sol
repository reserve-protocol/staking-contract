// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";

import { GenericStakedAppreciatingVault, RewardTracker, IERC20 } from "@src/staking/GenericStakedAppreciatingVault.sol";
import { ERC20Mock } from "@test/mocks/ERC20Mock.sol";

contract GenericStakedAppreciatingVaultTest is Test {
    ERC20Mock private token;
    GenericStakedAppreciatingVault private vault;

    uint8 private tokenDecimals;
    uint8 private vaultDecimals; // Also accounts for the inflation factor
    uint256 private maxError;

    address private DEPLOYER = address(0xff);
    address private USER1 = address(0x1);
    address private USER2 = address(0x2);

    function setUp() public {
        vm.startPrank(DEPLOYER);
        token = new ERC20Mock("Test Token", "TEST", 18);
        vault = new GenericStakedAppreciatingVault("Staked Test Token", "sTEST", IERC20(address(token)), 7 days);

        vaultDecimals = vault.decimals();
        tokenDecimals = token.decimals();

        assertTrue(vaultDecimals == tokenDecimals);
        maxError = 10 ** (vaultDecimals - tokenDecimals + 1);

        token.mint(DEPLOYER, 1000 * 10 ** tokenDecimals);
        token.transfer(USER1, 100 * 10 ** tokenDecimals);
        token.transfer(USER2, 100 * 10 ** tokenDecimals);
        vm.stopPrank();
    }

    function test_Deployment() public view {
        assertEq(vault.DISTRIBUTION_PERIOD(), 7 days);
        assertEq(vault.name(), "Staked Test Token");
        assertEq(vault.symbol(), "sTEST");
    }

    function _stakeAs(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeemAs(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.redeem(amount, user, user);
        vm.stopPrank();
    }

    function _addRewardsAs(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.addRewards(amount);
        vm.stopPrank();
    }

    function _triggerNextPeriod() internal {
        (, uint256 rewardPeriodEnd, ) = vault.rewardTracker();
        vm.warp(rewardPeriodEnd + 1);

        _addRewardsAs(DEPLOYER, 0);
    }

    function test_Distribution_Linear() public {
        _stakeAs(USER1, 100 * 10 ** tokenDecimals);

        // There's no rewards at this point, so 1:1 exchange rate.
        assertEq(vault.balanceOf(USER1), 100 * 10 ** vaultDecimals);
        assertEq(vault.previewRedeem(100 * 10 ** vaultDecimals), 100 * 10 ** tokenDecimals);

        // Let's add 700 tokens as rewards over 1 week
        // Remember these are added for the next period!
        _addRewardsAs(DEPLOYER, 700 * 10 ** tokenDecimals);

        _triggerNextPeriod();

        // Let's go forward by 1 day.
        vm.warp(block.timestamp + 1 days);

        // After 1 day, we expect to get 200 tokens
        assertApproxEqAbs(vault.previewRedeem(100 * 10 ** vaultDecimals), 200 * 10 ** tokenDecimals, maxError);

        // Let's go forward by another 6 days for a total of 1 week.
        vm.warp(block.timestamp + 6 days);

        // After 1 week, we should expect to get 800 tokens for our 100 tokens staked.
        assertApproxEqAbs(vault.previewRedeem(100 * 10 ** vaultDecimals), 800 * 10 ** tokenDecimals, maxError);
    }

    function test_Distribution_MultipleDeposits() public {
        _stakeAs(USER1, 100 * 10 ** tokenDecimals);

        _addRewardsAs(DEPLOYER, 700 * 10 ** tokenDecimals);

        _triggerNextPeriod();

        vm.warp(block.timestamp + 3.5 days);

        _stakeAs(USER2, 100 * 10 ** tokenDecimals);

        assertApproxEqAbs(vault.balanceOf(USER1), 100 * 10 ** vaultDecimals, maxError);
        assertApproxEqAbs(vault.balanceOf(USER2), (200 * 10 ** vaultDecimals) / 9, maxError); // 22.22222

        vm.warp(block.timestamp + 3.5 days);
        vm.warp(block.timestamp + 1);

        assertApproxEqAbs(vault.previewRedeem(100 * 10 ** vaultDecimals), 736 * 10 ** tokenDecimals, 1e18);
    }

    function test_Distribution_MultipleDepositRedeems() public {
        // Stake 100 tokens as user1
        _stakeAs(USER1, 100 * 10 ** tokenDecimals);

        // Add Rewards
        _addRewardsAs(DEPLOYER, 700 * 10 ** tokenDecimals);

        _triggerNextPeriod();

        // Half the distribution later...
        vm.warp(block.timestamp + 3.5 days);

        // ...user2 decides to stake 100 tokens!
        _stakeAs(USER2, 100 * 10 ** tokenDecimals);

        // Now since rewards have already been distributing...
        // User1's 100 shares are worth more. (deposited at 1:1)
        // So User2 staking 100 underlying should give him ~(100/4.5) shares ~22.22 shares
        assertApproxEqAbs(vault.balanceOf(USER1), 100 * 10 ** vaultDecimals, maxError);
        assertApproxEqAbs(vault.balanceOf(USER2), (200 * 10 ** vaultDecimals) / 9, maxError);

        // Let's make sure the current accounting is correct
        assertApproxEqAbs(vault.totalAssets(), 550 * 10 ** tokenDecimals, maxError);

        // 1 day later..
        vm.warp(block.timestamp + 1 days);

        // User1 decides to redeem 50 shares
        _redeemAs(USER1, 50 * 10 ** vaultDecimals);

        // At this point, User1 got 100/2 + 350/2 + ~81.8/2 = ~265.9 tokens back.
        assertApproxEqAbs(token.balanceOf(USER1), 265 * 10 ** tokenDecimals, 1e18);

        // Let's make sure the current accounting is correct
        // User1 has 50 shares left, User2 has 22.22 shares
        // Without withdrawal it would be ~650, so removing ~266 from it gives us ~384
        assertApproxEqAbs(vault.totalAssets(), 384 * 10 ** tokenDecimals, 1e18);

        // 2.5 day later.. (the end of the distribution period)
        vm.warp(block.timestamp + 2.5 days);

        // Let's make sure the current accounting is correct
        assertApproxEqAbs(vault.totalAssets(), 634 * 10 ** tokenDecimals, 1e18);

        // Let's make sure the overall vault appreciation in correct.
        assertApproxEqAbs(vault.previewRedeem(100 * 10 ** vaultDecimals), 877 * 10 ** tokenDecimals, 1e18);
    }
}
