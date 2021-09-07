const Rewardeum = artifacts.require("Rewardeum");
const Reum_airdrop = artifacts.require('Reum_airdrop');

module.exports = function(deployer, network) {
  if (network=="bsc") {
    deployer.then(async () => {
    await deployer.deploy(Reum_airdrop, "0x5A68431398A6DE785994441e206259702e259C5E");
    })
  }

};
