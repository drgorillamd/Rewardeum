const Parking = artifacts.require("Parking");

module.exports = function(deployer) {
    await deployer.deploy(Parking);
};
