const Web3 = require('web3');
const Provider = require('@truffle/hdwallet-provider');
const ContractBuild = require('../build/contracts/Presale.json');
const fs = require('fs');
const whiteList = fs.readFileSync("../data/whitelist.json").toString().split("\n").slice(0, -1);
const tmp = fs.readFileSync("/home/drgorilla/Documents/solidity/.private_key_burner").toString();
const owner = [tmp];
const RPC_SERVER = 'https://bsc-dataseed.binance.org';


async function add_wl() {
  try {
    const provider = new Provider(owner, RPC_SERVER);
    const web3 = new Web3(provider);
    const inst = await new web3.eth.Contract(ContractBuild.abi, ContractBuild.networks[56].address);
    await inst.methods.addWhitelist(whiteList).send({from: provider.addresses[0]});
    console.log("add from: "+provider.addresses);
  } catch (e) {
    console.log(e);
  }
}

add_wl();

process.on('exit', function(code) {
  return console.log(`Exit with code ${code}`);
});