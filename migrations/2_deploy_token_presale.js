const Migrations = artifacts.require("Migrations");
const projectX = artifacts.require("projectX");

const BSC_mainnet_routeur = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const BSC_test_routeur = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";

module.exports = function(deployer, network) {
  if (network=="testnet") {
    deployer.then(async () => {
      await deployer.deploy(projectX, BSC_test_routeur);
    })
  }
  else if (network=="bsc") {
    deployer.then(async () => {
      await deployer.deploy(projectX, BSC_mainnet_routeur);
    })
  }
  else if (network=="ganache") {
    deployer.then(async () => {
      await deployer.deploy(projectX, BSC_mainnet_routeur);
    })
  }
};
