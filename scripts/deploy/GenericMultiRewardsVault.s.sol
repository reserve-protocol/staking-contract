// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { GenericMultiRewardsVault, IERC20, IERC20Metadata } from "@src/rewards/GenericMultiRewardsVault.sol";

contract GenericMultiRewardsVaultDeployer is Script {
    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".seed");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        address walletAddress = vm.rememberKey(privateKey);

        vm.startBroadcast(privateKey);

        IERC20Metadata asset = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // TODO: REPLACE THIS!!!!

        GenericMultiRewardsVault vault = new GenericMultiRewardsVault(
            string(abi.encodePacked("Rewardable ", asset.name())),
            string(abi.encodePacked("r", asset.symbol())),
            IERC20(address(asset)),
            walletAddress
        );

        vm.stopBroadcast();
    }
}
