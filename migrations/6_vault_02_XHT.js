const vault_xht = artifacts.require('Vault_02');
const REWARDEUM_ORIG = "0x5A68431398A6DE785994441e206259702e259C5E";

module.exports = function(deployer, network) {
  if (network=="bsc") {
    deployer.then(async () => {
    await deployer.deploy(vault_xht, REWARDEUM_ORIG);
    })
  }

};
