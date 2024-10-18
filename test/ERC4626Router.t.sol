// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";

import { ERC4626Router, IERC4626 } from "@src/helper/ERC4626Router.sol";
import { GenericStakedAppreciatingVault, RewardTracker, IERC20 } from "@src/staking/GenericStakedAppreciatingVault.sol";
import { GenericMultiRewardsVault, IERC20, IERC20Metadata, SCALAR } from "@src/rewards/GenericMultiRewardsVault.sol";

import { ERC20Mock } from "@test/mocks/ERC20Mock.sol";

contract ERC4626RouterTest is Test {
    ERC20Mock private token;

    GenericStakedAppreciatingVault private stakingVault;
    GenericMultiRewardsVault private rewardsVault;

    ERC4626Router private router;

    address private USER1 = address(0x1);

    function setUp() public {
        token = new ERC20Mock("Test Token", "TEST", 18);
        stakingVault = new GenericStakedAppreciatingVault("Staked Test Token", "sTEST", IERC20(address(token)), 7 days);
        rewardsVault = new GenericMultiRewardsVault(
            "Rewardable Staked Test Token",
            "rsTEST",
            IERC20(address(stakingVault)),
            address(this)
        );

        router = new ERC4626Router();
    }

    function test_ChainedDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        token.mint(USER1, depositAmount);

        vm.startPrank(USER1);
        IERC4626[] memory vaults = new IERC4626[](2);
        vaults[0] = stakingVault;
        vaults[1] = rewardsVault;

        token.approve(address(router), type(uint256).max);
        router.depositChained(vaults, depositAmount);
        vm.stopPrank();

        assertEq(rewardsVault.balanceOf(USER1), depositAmount);
    }
}
