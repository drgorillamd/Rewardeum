const VaultLast = artifacts.require('VaultLast');
const REWARDEUM_ORIG = "0x5A68431398A6DE785994441e206259702e259C5E";

module.exports = function(deployer, network) {
  if (network=="bsc") {
    deployer.then(async () => {
        await deployer.deploy(VaultLast, REWARDEUM_ORIG);
    })
  }
};
