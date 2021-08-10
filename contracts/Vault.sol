// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vault is Ownable {

    constructor()

    function claim(string memory ticker, address dest) external returns (bool) {
        require(msg.sender == tokenX, "Vault: unauthorized access");
    }

}