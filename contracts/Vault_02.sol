// SPDX-License-Identifier: GPL
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./XHT_Ticket.sol";

/// @title Rewardeum Vault v02
/// @author DrGorilla_md (Tg/Twtr)
/// @notice vault: minting lottery tickets to win $rsun NFT
/// @dev contract proxied by the main Reum contract, in order to upgrade vault to new reward mecanisms
/// on a per-asset basis.
/// Iteration 01 - $XHT partnership: lottery tickets for RSUN NFT
contract Vault_02 is Ownable {

    uint256 public ticket_A_price = 100000000000000000;
    uint256 public ticket_B_price = 10000000000000000;
    uint256 public BNB_total_A;
    uint256 public BNB_total_B;


    address main_contract;
    XHT_Ticket public ticket_A_contract;
    XHT_Ticket public ticket_B_contract;

    constructor(address reum) {
        main_contract = reum;
        ticket_A_contract = new XHT_Ticket("REUM-XHT-A", 100);
        ticket_B_contract = new XHT_Ticket("REUM-XHT-B", 500);
    }

    /// @notice custom claim, only called by the main_contract 
    /// @dev this part is updated as needed then redeployed/proxied by main
    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (uint256) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

        if(ticker == bytes32("XHT-A")) {
            uint256 NFT_claimable = claimable / ticket_A_price;
            if(NFT_claimable > 0 && ticket_A_contract.isRunning()) ticket_A_contract.mintTicket(dest, NFT_claimable);
            BNB_total_A += claimable;
            return 0; //all the claimable amount remains
        }

        else if(ticker == bytes32("XHT-B")) {
            uint256 NFT_claimable = claimable / ticket_B_price;
            if(NFT_claimable > 0 && ticket_B_contract.isRunning()) ticket_B_contract.mintTicket(dest, NFT_claimable);
            BNB_total_B += claimable;
            return 0; //all the claimable amount remains
        }

        else revert("Vault: Invalid ticker");
    }

    function pending_tickets(uint256 amount_claimable) external view returns (uint256[2] memory) {
        uint256 amt_A = amount_claimable / ticket_A_price;
        uint256 amt_B = amount_claimable / ticket_B_price;
        return [amt_A, amt_B];
    }

    function stopA() external onlyOwner {
        ticket_A_contract.hardStop();
    }

    function stopB() external onlyOwner {
        ticket_B_contract.hardStop();
    }

    function changeEndA(uint256 _new) external onlyOwner {
        ticket_A_contract.changeEnd(_new);
    }

    function changeEndB(uint256 _new) external onlyOwner {
        ticket_B_contract.changeEnd(_new);
    }

    function changePrices(uint256 _A, uint256 _B) external onlyOwner {
        ticket_A_price = _A;
        ticket_B_price = _B;
    }

    receive () external payable {
        revert("Vault: non payable");
    }

}