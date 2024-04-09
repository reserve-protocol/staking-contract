import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ONE_WEEK = 60 * 60 * 24 * 7;

const StakingVaultModule = buildModule("StakingVaultModule", (m) => {
  const distributionPeriod = m.getParameter("distributionPeriod", ONE_WEEK);

  const underlyingAsset = m.getParameter("underlyingAsset");
  const vaultName = m.getParameter("vaultName");
  const vaultSymbol = m.getParameter("vaultSymbol");

  const stakingVault = m.contract("GenericStakedAppreciatingVault", [
    vaultName,
    vaultSymbol,
    underlyingAsset,
    distributionPeriod,
  ]);

  return { stakingVault };
});

export default StakingVaultModule;
