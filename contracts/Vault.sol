// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract Vault is Ownable, ERC721Holder {

    address main_contract;

    constructor(address reum) {
        main_contract = reum;
    }

    function claim(string memory ticker, address dest) external returns (bool) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

    }

}