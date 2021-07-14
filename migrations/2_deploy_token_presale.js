const Migrations = artifacts.require("Migrations");
const iBNB = artifacts.require("iBNB");
const iBNBPresale = artifacts.require("iBNB_presale");

const BSC_mainnet_routeur = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BSC_test_routeur = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";

module.exports = function(deployer, network) {
  if (network=="testnet") {
    deployer.then(async () => {
      await deployer.deploy(iBNB, BSC_test_routeur);
      await deployer.deploy(iBNBPresale, BSC_test_routeur, iBNB.address);
    })
  }
  else if (network=="bsc") {
    deployer.then(async () => {
      await deployer.deploy(iBNB, BSC_mainnet_routeur);
      await deployer.deploy(iBNBPresale, BSC_mainnet_routeur, iBNB.address);
    })
  }
  else if (network=="ganache") {
    deployer.then(async () => {
      await deployer.deploy(iBNB, BSC_mainnet_routeur);
      await deployer.deploy(iBNBPresale, BSC_mainnet_routeur, iBNB.address);
    })
  }
};
