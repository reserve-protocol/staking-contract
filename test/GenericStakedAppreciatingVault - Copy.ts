import hre from "hardhat";
import { expect } from "chai";

import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";

import StakingVaultModule from "$/modules/GenericStakedAppreciatingVault";
import { parseUnits } from "viem";

async function deployVaultFixture() {
  const testingToken = await hre.viem.deployContract("ERC20Mock", ["Test Token", "TEST"]);

  const { stakingVault } = await hre.ignition.deploy(StakingVaultModule, {
    parameters: {
      StakingVaultModule: {
        underlyingAsset: testingToken.address,
        vaultName: "Staked Test Token",
        vaultSymbol: "sTEST",
      },
    },
  });

  return { stakingVault, token: testingToken };
}

describe("Generic Staked Appreciating Vault", function () {
  describe("Deployment", function () {
    it("Should set the right name & symbol", async function () {
      const { stakingVault, token } = await loadFixture(deployVaultFixture);

      expect(await stakingVault.read.name()).to.equal(`Staked ${await token.read.name()}`);
      expect(await stakingVault.read.symbol()).to.equal(`s${await token.read.symbol()}`);
    });

    it("Should set the right distribution period", async function () {
      const { stakingVault } = await loadFixture(deployVaultFixture);

      expect(await stakingVault.read.REWARDS_DURATION()).to.equal(BigInt(60 * 60 * 24 * 7));
    });
  });

  describe("Distribution", function () {
    let stakingVault: Awaited<ReturnType<typeof deployVaultFixture>>["stakingVault"];
    let token: Awaited<ReturnType<typeof deployVaultFixture>>["token"];

    before(async function () {
      ({ stakingVault, token } = await loadFixture(deployVaultFixture));

      const [deployer, user] = await hre.viem.getWalletClients();

      await token.write.mint([deployer.account.address, parseUnits("1000", 18)]);
      await token.write.transfer([user.account.address, parseUnits("100", 18)]); // Transfer 100 tokens to the user
    });

    it("Linear Distribution", async function () {
      const [deployer, user] = await hre.viem.getWalletClients();

      // Let's stake 100 tokens
      await token.write.approve([stakingVault.address, parseUnits("100", 18)], {
        account: user.account,
      });
      await stakingVault.write.deposit([parseUnits("100", 18), user.account.address], {
        account: user.account,
      });
      console.log(await stakingVault.read.totalAssets());

      // There's no rewards at this point, so 1:1 exchange rate.
      expect(await stakingVault.read.balanceOf([user.account.address])).to.equal(parseUnits("100", 18));
      expect(await stakingVault.read.previewWithdraw([parseUnits("100", 18)])).to.equal(parseUnits("100", 18));

      // Let's add 700 tokens as rewards over 1 week
      await token.write.approve([stakingVault.address, parseUnits("700", 18)]);
      await stakingVault.write.accountRewards([parseUnits("700", 18)]);

      // Let's go forward by 1 day.
      await time.increase(BigInt(60 * 60 * 24));
      // After 1 day, we expect to get 200 tokens
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("199", 18)).to.be.true;

      // Let's go forward by another 6 days for a total of 1 week.
      await time.increase(BigInt(60 * 60 * 24 * 6));
      // After 1 week, we should expect to get 800 tokens for our 100 tokens staked.
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("799", 18)).to.be.true;

      await time.increase(100);

      console.log(await stakingVault.read.totalAssets());
    });
  });
});
