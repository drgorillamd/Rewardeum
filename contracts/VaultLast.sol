// SPDX-License-Identifier: GPL
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./REUMGenericTicket.sol";

/// @title Rewardeum Vault - Last iteration
/// @author DrGorilla_md (Tg/Twtr)
/// @notice vault: minting lottery tickets
/// @dev contract proxied by the main Reum contract, in order to upgrade vault to new reward mecanisms
/// on a per-asset basis (deprecated: last version - no other mechanism than lottery per team agreement)
contract VaultLast {

    uint256 current_id;

    address main_contract;

    mapping(bytes32 => REUMGenericTicket) public active_contracts;
    mapping(bytes32 => uint256) public prices;

    mapping(address => bool) owners;
    modifier onlyOwner {
        require(owners[msg.sender], "Not owner");
        _;
    }

    constructor(address reum) {
        main_contract = reum;
        owners[msg.sender] = true;
    }

    function newLottery(bytes32 ticker, uint256 price, uint256 deadline, uint256 nb_tickets) external onlyOwner {
        active_contracts[ticker] = new REUMGenericTicket(deadline, nb_tickets, current_id);
        prices[ticker] = price;
        current_id++;
    }

    function deleteLottery(bytes32 ticker) external onlyOwner {
        delete active_contracts[ticker];
        delete prices[ticker];
    }

    /// @notice custom claim, only called by the main_contract 
    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (uint256) {
        require(msg.sender == main_contract, "Vault: unauthorized access");
        require(active_contracts[ticker] != REUMGenericTicket(payable(0)), "Vault: invalid ticker");

        uint256 ticket_claimable = claimable / prices[ticker];
        if(ticket_claimable > 0 && active_contracts[ticker].isRunning()) active_contracts[ticker].mintTicket(dest, ticket_claimable);
        //if no more ticket, still processing the token claim (in main contract)
        return 0; //all the claimable amount remains
    }

    function pending_tickets(uint256 amount_claimable, bytes32 ticker) external view returns (uint256) {
        return amount_claimable / prices[ticker];
    }

    function stop(bytes32 ticker) external onlyOwner {
        active_contracts[ticker].hardStop();
    }

    function setOwner(address _adr, bool isOwner) external onlyOwner {
        owners[_adr] = isOwner;
    }

    receive () external payable {
        revert("Vault: non payable");
    }

}