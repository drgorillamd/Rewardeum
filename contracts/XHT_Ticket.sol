// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @title Rewardeum Lottery Ticket
/// @author DrGorilla_md (Tg/Twtr)
/// @notice NFT Lottery ticket for the first Rewardeum Vault iteration
/// @dev inherit the abstract contract ERC721Enumerable to have tokenOfOwnerByIndex() and totalSupply()
/// for the frontend integration.

contract XHT_Ticket is ERC721Enumerable, Ownable {

    string contract_URI_shop;
    uint256 private _tokenIds;
    uint256 public nb_tickets_max;
    uint256 public end;
    bool running;

    constructor(string memory symb, uint256 _max) ERC721("LOTTERY", symb) {
        contract_URI_shop = "https://www.rewardeum.com/images/contract_uri.json";
        running = true;
        nb_tickets_max = _max;
        end = block.timestamp + 7 days;
    }

    function mintTicket(address receiver, uint256 nb_tickets) external onlyOwner {
        uint256 curr_id = _tokenIds;

        if(block.timestamp >= end || curr_id > nb_tickets_max) running = false; //08-Sep-2021 21:00 UTC
        require(running, "Minting not active anymore");

        uint256 nb_nft = curr_id + nb_tickets >= nb_tickets_max ? nb_tickets_max - curr_id : nb_tickets;    

        for (uint i = 0; i < nb_nft; i++) {
            curr_id++;
            _mint(receiver, curr_id);
        }
        _tokenIds = curr_id;

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

    function isRunning() external view returns (bool) {
        return running;
    }

    function hardStop() public onlyOwner {
        running = false;
    }

    function changeEnd(uint256 _new) public onlyOwner {
        end = _new;
    }

    receive () external payable {
        revert("REUM Lottery: non payable");
    }

}