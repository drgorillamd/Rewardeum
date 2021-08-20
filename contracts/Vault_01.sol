// SPDX-License-Identifier: GPL
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./REUM_ticket.sol";

/// @title Rewardeum Vault v01
/// @author DrGorilla_md (Tg/Twtr)
/// @notice vault: minting lottery tickets to win $rsun NFT
/// @dev contract proxied by the main Reum contract, in order to upgrade vault to new reward mecanisms
/// on a per-asset basis
/// Iteration 01 - $RSUN partnership: lottery tickets for RSUN NFT
contract Vault_01 is Ownable {

    uint256 ticket_price = 0;
    address main_contract;
    REUM_ticket ticket_contract;

    constructor(address reum) {
        main_contract = reum;
        ticket_contract = new REUM_ticket();
    }

    /// @notice custom claim, only called by the main_contract 
    /// @dev this part is updated as needed then redeployed/proxied by main
    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (bool) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

        if(ticker == bytes32("RSUN")) {
            uint256 NFT_claimable = claimable / ticket_price;
            if(NFT_claimable > 0) ticket_contract.mintTicket(dest, NFT_claimable);
            return true;
        }

        else revert("Vault: Invalid ticker");
    }

    function pending_tickets(uint256 amount_claimable) external view returns (uint256) {
        return amount_claimable / ticket_price;
    }

    receive () external payable {
        revert("Vault: non payable");
    }

}