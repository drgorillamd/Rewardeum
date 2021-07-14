const Migrations = artifacts.require("Migrations");
const iBNB = artifacts.require("iBNB");
const iBNB_airdrop = artifacts.require("iBNB_airdrop");

module.exports = function(deployer) {
    await deployer.deploy(iBNB_airdrop, "0x830F7A104a3dF30879D526031D57DAa44BF85686");
};
