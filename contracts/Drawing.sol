// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @title Rewardeum Lottery Drawing
/// @author DrGorilla_md (Tg/Twtr)
/// @notice Will pick the five lucky winners
/// @dev Will pick five int between 0 and totalSupply() and return their owner address

contract Drawing is Ownable {

    bool active = true;

    IERC721Enumerable ticket;
    IERC20 token_interface;

    uint256[5] public ids;
    address[5] public  addresses;

    constructor() {
        ticket = IERC721Enumerable(0xfc926845b0D6A9e726db5bEf1255BDb2328A95C5);
        token_interface = IERC20(0x5A68431398A6DE785994441e206259702e259C5E);
    }

    function winners(uint256 seed) public onlyOwner {
        require(active, "Winners already decided");
        
        ids = random(seed);
        for(uint256 i=0; i<5; i++) {
            addresses[i] = ticket.ownerOf(ids[i]);
        }
        active = false;
    }

    function getWinners() external view returns (uint256[5] memory, address[5] memory) {
        return (ids, addresses);
    }

/// @dev low quality randomness since low probablity of being frontrun to have an atomic
/// auction+transfer of the winning NFT ticket

    function random(uint256 seed) public view returns (uint256[5] memory expandedValues) {
        uint256 total_supply = ticket.totalSupply();
        uint256 contract_balance = token_interface.balanceOf(address(token_interface));
        uint256 contract_bnb = address(token_interface).balance;

        uint256 baseRandom = uint256(keccak256(abi.encode(seed, total_supply, msg.sender, contract_balance, contract_bnb)));

        for (uint256 i = 0; i < 5; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(baseRandom, i))) % total_supply;
        }
        return expandedValues;
    }


    receive () external payable {
        revert("non payable");
    }

}
