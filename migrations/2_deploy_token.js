const Migrations = artifacts.require("Migrations");
const Rewardeum = artifacts.require("Rewardeum");
const vault_rsun = artifacts.require('Vault_01');
const Reum_presale = artifacts.require('Reum_presale');
const Reum_airdrop = artifacts.require('Reum_airdrop');


const BSC_mainnet_routeur = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

module.exports = function(deployer, network) {
  if (network=="bsc") {
    deployer.then(async () => {
    await deployer.deploy(Rewardeum, BSC_mainnet_routeur);
    await deployer.deploy(Reum_presale, BSC_mainnet_routeur, Rewardeum.address);
    //await deployer.deploy(Reum_airdrop, Rewardeum.address);
    await deployer.deploy(vault_rsun, Rewardeum.address);
    })
  }

};
