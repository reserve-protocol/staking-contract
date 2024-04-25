// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { IERC20Metadata } from "@src/rewards/GenericMultiRewardsVault.sol";
import { GenericStakedAppreciatingVault, IERC20 } from "@src/staking/GenericStakedAppreciatingVault.sol";

contract GenericStakedAppreciatingVaultDeployer is Script {
    function setUp() public {}

    function run() public {
        string memory seedPhrase = vm.readFile(".seed");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        address walletAddress = vm.rememberKey(privateKey);

        vm.startBroadcast(privateKey);

        IERC20Metadata asset = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // TODO: REPLACE THIS!!!!

        GenericStakedAppreciatingVault vault = new GenericStakedAppreciatingVault(
            string(abi.encodePacked("Staked ", asset.name())),
            string(abi.encodePacked("s", asset.symbol())),
            IERC20(address(asset)),
            14 days
        );

        vm.stopBroadcast();
    }
}
