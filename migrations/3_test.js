const Migrations = artifacts.require("Migrations");
const Rewardeum = artifacts.require("Rewardeum");
const vault = artifacts.require('Vault_01');

const BSC_mainnet_routeur = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BSC_test_routeur = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";


module.exports = function(deployer, network) {
  if (network=="ganache") {
      deployer.then(async () => {
        await deployer.deploy(Rewardeum, BSC_mainnet_routeur);
        await deployer.deploy(vault, Rewardeum.address);
        await deployer.deploy(nft);
        await deployer.deploy(Reum_presale, BSC_mainnet_routeur, Rewardeum.address);
        await deployer.deploy(Reum_airdrop, Rewardeum.address);
      })

  }
  else if (network=="testnet") {
    deployer.then(async () => {
      await deployer.deploy(Rewardeum, BSC_test_routeur);
      await deployer.deploy(vault, Rewardeum.address);
    })
  }

};
