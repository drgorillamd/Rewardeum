// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @title Rewardeum Lottery Ticket
/// @author DrGorilla_md (Tg/Twtr)
/// @notice NFT Lottery ticket for the first Rewardeum Vault iteration
/// @dev inherit the abstract contract ERC721Enumerable to have tokenOfOwnerByIndex() and totalSupply()
/// for the frontend integration.

contract REUM_ticket is ERC721Enumerable, Ownable {

    string contract_URI_shop;
    uint256 private _tokenIds;
    uint256 public nb_tickets_max = 10000;

    constructor() ERC721("LOTTERY", "REUMxRSUN") {
        contract_URI_shop = "https://www.rewardeum.com/images/contract_uri.json";
    }

    function mintTicket(address receiver, uint256 nb_tickets) external onlyOwner {

        uint256 curr_supply = _tokenIds;
        require(curr_supply < nb_tickets_max, "No more tickets to mint");
        uint256 nb_nft = curr_supply + nb_tickets >= nb_tickets_max ? nb_tickets_max - curr_supply : nb_tickets;    

        for (uint i = 0; i < nb_nft; i++) {
            _tokenIds++;
            _mint(receiver, _tokenIds);
        }

    }

    function tokenURI(uint256 token_id) public view override returns (string memory) {
        require(_exists(token_id), "Invalid ticket number");
        return "https://www.rewardeum.com/images/metadata.json";
    }

    function setContractUriShop(string memory new_contract_uri) public onlyOwner {
        contract_URI_shop = new_contract_uri;
    }

    function contractURI() public view returns (string memory) {
        return contract_URI_shop;
    }

    receive () external payable {
        revert("REUM Lottery: non payable");
    }

}