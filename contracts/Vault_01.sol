// SPDX-License-Identifier: GPL
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title Rewardeum Vault v01
/// @author DrGorilla_md (Tg/Twtr)
/// @notice initial vault: minting lottery tickets to win $rsun
/// @dev contract proxied by the main Reum contract, in order to upgrade vault to new reward mecanisms
/// on a per-asset basis
/// Iteration 01 - $RSUN partnership: lottery tickets
contract Vault_01 is Ownable {

    address main_contract;

    event VaultError(string);

    constructor(address reum) {
        main_contract = reum;
        //ticket_contract = new ERC721("REUM-RSUN Lottery", "TICKET");
    }

    /// @notice custom claim, only called by the main_contract 
    /// @dev this part should be updated as needed then redeployed
    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (bool) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

        if(ticker == bytes32("RSUN")) {

                return true;
 
        }
        else return false;
    }

/*    function syncNFTEnum(bytes32 ticker) external {
        IERC721Enumerable INFT = IERC721Enumerable(current_asset[bytes32(ticker)]);
        uint256 num_token = INFT.balanceOf(address(this));
        uint256[] memory _ids = new uint256[](num_token-1);
        for(uint i; i<num_token; i++) _ids[i] = INFT.tokenOfOwnerByIndex(address(this), i);
        NFT_tokenID[bytes32(ticker)] = _ids;
    }

    function syncNFTNonEnum(bytes32 ticker, uint256[] memory _ids) external onlyOwner {
        NFT_tokenID[bytes32(ticker)] = _ids;
    }*/
    receive () external payable {
        revert();
    }

}

/*

    uint256 MAX_ID = 15;
    address recipient = 0x7BEBF57FAfcB0Df8E03647CBfF6DAb1b6CD2d53D;

    constructor() ERC721("RSUN REUM Lottery", "Ticket") {
    	for (uint i = 1; i<=MAX_ID; i++) {
    		_tokenIds.increment();
        	_mint(recipient, _tokenIds.current());
        }
    }


    function tokenURI(uint256 token_id) public view override returns (string memory) {
    	require(_exists(token_id), "ERC721Metadata: URI query for nonexistent token");
        return "https://ipfs.io/ipfs/QmZqyrFhJgbjtgVPikNcJnZHMz6tuA4xvguXNjrVhYwbbp";
    }


    function totalSupply() external view returns (uint256) {
      return MAX_ID;
    }
*/
