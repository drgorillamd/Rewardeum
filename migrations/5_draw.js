const Drawing = artifacts.require('Drawing');
const Migrations = artifacts.require("Migrations");


module.exports = function(deployer) {
  deployer.deploy(Drawing);
};
