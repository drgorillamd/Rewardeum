// SPDX-License-Identifier: GPL - Author: @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Reum_airdrop is Ownable {

    IERC20 token_interface;

    constructor (address _contract) {
        token_interface = IERC20(_contract);
        require(token_interface.totalSupply() != 0, "invalide erc20");
    }

    function send_airdrop(address sender, address[] calldata _receivers, uint256[] calldata _balances) external onlyOwner {
        for(uint256 i = 0; i<_receivers.length; i++) {
            token_interface.transferFrom(sender, _receivers[i], _balances[i]*10**9); //quick and dirty dec fix
        }
    }
}
