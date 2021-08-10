pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";


contract vault_test_NFT is ERC721 {

    uint256 MAX_ID = 15;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    constructor() ERC721("Vault_test", "TEST") {
    	for (uint i = 1; i<=MAX_ID; i++) {
    		_tokenIds.increment();
        	_mint(msg.sender, _tokenIds.current());
        }
    }

    function tokenURI(uint256 token_id) public view override returns (string memory) {
    	require(_exists(token_id), "ERC721Metadata: URI query for nonexistent token");
        return "https://ipfs.io/ipfs/1";
    }

    function totalSupply() external view returns (uint256) {
      return MAX_ID;
    }


}
