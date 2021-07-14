// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Parking is Ownable {

    IERC20 iBNB_contract = IERC20(0x830F7A104a3dF30879D526031D57DAa44BF85686);

    constructor () {
    }

    function retrieve(address[] calldata _receivers, uint256[] calldata _balances) external onlyOwner {
        
        for(uint256 i = 0; i<_receivers.length; i++) {
            iBNB_contract.transfer(_receivers[i], _balances[i]*10**9); //quick and dirty dec fix
        }
        selfdestruct(payable(msg.sender)); //let's enjoy while it last
    }

}
