const Migrations = artifacts.require("Migrations");
const Rewardeum = artifacts.require("Rewardeum");
const vault = artifacts.require('Vault_01');
const nft = artifacts.require('vault_test_NFT');
const Reum_presale = artifacts.require('Reum_presale');
const Reum_airdrop = artifacts.require('Reum_airdrop');

const BSC_mainnet_routeur = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

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

};
