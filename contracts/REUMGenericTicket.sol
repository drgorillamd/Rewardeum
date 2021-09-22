// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @title Rewardeum Lottery Ticket
/// @author DrGorilla_md (Tg/Twtr)
/// @notice NFT Lottery ticket for the Rewardeum Vault
/// @dev inherit the abstract contract ERC721Enumerable to have tokenOfOwnerByIndex() and totalSupply()
/// for the frontend integration.

contract REUMGenericTicket is ERC721Enumerable, Ownable {

    uint256 private _tokenIds;
    uint256 public nb_tickets_max;
    uint256 id;
    bool running;
    uint256 public deadline;

    constructor(uint256 _deadline, uint256 _max, uint256 _id) ERC721("LOTTERY", "REUMxRSUN") {
        running = true;
        deadline = _deadline;
        nb_tickets_max = _max;
        id = _id;
    }

    function mintTicket(address receiver, uint256 nb_tickets) external onlyOwner {
        uint256 curr_id = _tokenIds;

        if(block.timestamp >= deadline || curr_id > nb_tickets_max) running = false;
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
        return string(abi.encodePacked("https://www.rewardeum.com/images/metadata", id, ".json"));
    }


    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked("https://www.rewardeum.com/images/contract_uri", id, ".json"));
    }

    function isRunning() external view returns (bool) {
        return running;
    }

    function hardStop() public onlyOwner {
        running = false;
    }

    receive () external payable {
        revert("REUM Lottery: non payable");
    }

}