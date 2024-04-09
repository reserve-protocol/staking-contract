import hre from "hardhat";
import { expect } from "chai";

import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";

import StakingVaultModule from "$/modules/GenericStakedAppreciatingVault";
import { parseUnits } from "viem";
import { WalletClient } from "@nomicfoundation/hardhat-viem/types";

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

      expect(await stakingVault.read.DISTRIBUTION_PERIOD()).to.equal(BigInt(60 * 60 * 24 * 7));
    });
  });

  describe("Distribution", function () {
    let stakingVault: Awaited<ReturnType<typeof deployVaultFixture>>["stakingVault"];
    let token: Awaited<ReturnType<typeof deployVaultFixture>>["token"];

    beforeEach(async function () {
      ({ stakingVault, token } = await loadFixture(deployVaultFixture));

      const [deployer, user1, user2] = await hre.viem.getWalletClients();

      await token.write.mint([deployer.account.address, parseUnits("1000", 18)]);
      await token.write.transfer([user1.account.address, parseUnits("100", 18)]); // Transfer 100 tokens to the user1
      await token.write.transfer([user2.account.address, parseUnits("100", 18)]); // Transfer 100 tokens to the user2
    });

    async function stakeAs(user: WalletClient, amount: bigint) {
      await token.write.approve([stakingVault.address, amount], {
        account: user.account,
      });
      await stakingVault.write.deposit([amount, user.account.address], {
        account: user.account,
      });
    }

    async function redeemAs(user: WalletClient, amount: bigint) {
      await stakingVault.write.redeem([amount, user.account.address, user.account.address], {
        account: user.account,
      });
    }

    async function addRewardsAsDeployer(amount: bigint) {
      await token.write.approve([stakingVault.address, amount]);
      await stakingVault.write.addRewards([amount]);
    }

    it("Linear Distribution", async function () {
      const [deployer, user] = await hre.viem.getWalletClients();

      await stakeAs(user, parseUnits("100", 18));

      // There's no rewards at this point, so 1:1 exchange rate.
      expect(await stakingVault.read.balanceOf([user.account.address])).to.equal(parseUnits("100", 18));
      expect(await stakingVault.read.previewWithdraw([parseUnits("100", 18)])).to.equal(parseUnits("100", 18));

      // Let's add 700 tokens as rewards over 1 week
      await addRewardsAsDeployer(parseUnits("700", 18));

      // Let's go forward by 1 day.
      await time.increase(BigInt(60 * 60 * 24));
      // After 1 day, we expect to get 200 tokens
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("199", 18)).to.be.true;

      // Let's go forward by another 6 days for a total of 1 week.
      await time.increase(BigInt(60 * 60 * 24 * 6));
      // After 1 week, we should expect to get 800 tokens for our 100 tokens staked.
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("799", 18)).to.be.true;
    });

    it("Complex Scenario - Multiple Deposits", async function () {
      const [deployer, user1, user2] = await hre.viem.getWalletClients();

      // Stake 100 tokens as user1
      await stakeAs(user1, parseUnits("100", 18));

      // Add Rewards
      await addRewardsAsDeployer(parseUnits("700", 18));

      // Half the distribution later...
      await time.increase(BigInt(60 * 60 * 24 * 3.5)); // Half the duration

      // ...user2 decides to stake 100 tokens!
      await stakeAs(user2, parseUnits("100", 18));

      // Now since rewards have already been distributing...
      // User1's 100 shares are worth more. (deposited at 1:1)
      // So User2 staking 100 underlying should give him ~(100/4.5) shares ~22.22 shares
      expect((await stakingVault.read.balanceOf([user1.account.address])) === parseUnits("100", 18)).to.be.true;
      expect((await stakingVault.read.balanceOf([user2.account.address])) > parseUnits("22", 18)).to.be.true;
      expect((await stakingVault.read.balanceOf([user2.account.address])) < parseUnits("22.5", 18)).to.be.true;

      // Another 3.5 days later...
      await time.increase(BigInt(60 * 60 * 24 * 3.5));
      await time.increase(1);

      // Let's make sure the overall vault appreciation in correct.
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("449", 18)).to.be.true;
    });

    it("Complex Scenario - Multiple Deposits & Withdrawals", async function () {
      const [deployer, user1, user2] = await hre.viem.getWalletClients();

      // Stake 100 tokens as user1
      await stakeAs(user1, parseUnits("100", 18));

      // Add Rewards
      await addRewardsAsDeployer(parseUnits("700", 18));

      // Half the distribution later...
      await time.increase(BigInt(60 * 60 * 24 * 3.5)); // Half the duration

      // ...user2 decides to stake 100 tokens!
      await stakeAs(user2, parseUnits("100", 18));

      // Now since rewards have already been distributing...
      // User1's 100 shares are worth more. (deposited at 1:1)
      // So User2 staking 100 underlying should give him ~(100/4.5) shares ~22.22 shares
      expect((await stakingVault.read.balanceOf([user1.account.address])) === parseUnits("100", 18)).to.be.true;
      expect((await stakingVault.read.balanceOf([user2.account.address])) > parseUnits("22", 18)).to.be.true;
      expect((await stakingVault.read.balanceOf([user2.account.address])) < parseUnits("22.5", 18)).to.be.true;

      // Let's make sure the current accounting is correct
      expect((await stakingVault.read.totalAssets()) >= parseUnits("550", 18)).to.be.true;
      expect((await stakingVault.read.totalAssets()) < parseUnits("551", 18)).to.be.true;

      // 1 day later..
      await time.increase(BigInt(60 * 60 * 24 * 1));

      // User1 decides to redeem 50 shares
      await redeemAs(user1, parseUnits("50", 18));

      // At this point, User1 got 100/2 + 350/2 + ~81.8/2 = ~265.9 tokens back.
      expect((await token.read.balanceOf([user1.account.address])) > parseUnits("265.9", 18)).to.be.true;
      expect((await token.read.balanceOf([user1.account.address])) < parseUnits("266", 18)).to.be.true;

      // Let's make sure the current accounting is correct
      // User1 has 50 shares left, User2 has 22.22 shares
      // Without withdrawal it would be ~650, so removing ~266 from it gives us ~384
      expect((await stakingVault.read.totalAssets()) >= parseUnits("384", 18)).to.be.true;
      expect((await stakingVault.read.totalAssets()) < parseUnits("385", 18)).to.be.true;

      // 2.5 day later.. (the end of the distribution period)
      await time.increase(BigInt(60 * 60 * 24 * 2.5));

      // Let's make sure the current accounting is correct
      expect((await stakingVault.read.totalAssets()) >= parseUnits("634", 18)).to.be.true;

      // Let's make sure the overall vault appreciation in correct.
      // TODO: Recheck this math please!!!
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) > parseUnits("877", 18)).to.be.true;
      expect((await stakingVault.read.previewRedeem([parseUnits("100", 18)])) < parseUnits("878", 18)).to.be.true;
    });

    it("Last Depositor", async function () {
      // TODO: Last depositor must always get all the rewards regardless of distribution.
    });
  });
});
