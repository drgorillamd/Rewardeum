## Rewardeum(REUM)

# Main contract: Rewardeum.sol

ERC20 compliant token with taxes on transfer, funding a double reward pool system:
- Reward pool
- Reserve
 Every user can claim every 24h a reward, based on the share of the total supply owned. The token
 claimed is either BNB or any other available token (from a curated list).
 An additional incentive mechanism (the "Vault") offer extra reward on chosen claimable tokens.
 The contract is custodial for BNB and $reum (swapped for BNB in batches), custom token 
 are swapped as needed. Main contract act as a proxy for the vault (via IVault) which is redeployed
 for new offers. Tickers are stored in bytes32 for gas optim (frontend integration via web3.utils.hexToAscii and asciiToHex)

# Generic vault template: Vault.sol

Used for unit tests, in combination with test_NFT.sol

# Vault iterations :
- Vault_01.sol : first partnership, calling REUM_ticket.sol (generic ERC721Enumerable) to mint lottery tickets when claiming

# Presale.sol

Presale contract

# Airdrops.sol

Airdropper


# To run the tests, clone this repo and run npm i first, set higher gas limit in Ganache

ganache-cli -f https://bsc-dataseed.binance.org/ -l 20000000000000
In a new terminal : truffle test --network ganache
