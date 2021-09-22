// SPDX-License-Identifier: GPL
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/Extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";


/// @title Rewardeum Vault
/// @author DrGorilla_md (Tg/Twtr)
/// @dev contract proxied by the main Reum contract, in order to upgrade vault to new reward mecanisms
/// on a per-asset basis
/// Iteration 2 - Minority Vault Game
contract Vault02Minority is Ownable {

    uint256 public tot_vote_A;
    uint256 public tot_vote_B;
    uint256 winner;
    uint256 total_locked;

    bool public voting;

    address main_contract;

    struct voteStruct {
        uint256 vote_A;
        uint256 vote_B;
        bool withdrew;
    }

    mapping (address => voteStruct) public vote_by_address;

    IERC20 IReum;

    constructor(address reum) {
        main_contract = reum;
        IReum = IERC20(main_contract);
    }


    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (uint256 claim_consumed) {
        require(msg.sender == main_contract, "Vault: unauthorized access");
        require(voting, "Voting is not active");

        if(ticker == bytes32("REUM-A")) {
            tot_vote_A += claimable;
            vote_by_address[dest].vote_A += claimable;
            return claimable / 2;
        }

        else if(ticker == bytes32("REUM-B")) {
            tot_vote_B += claimable;
            vote_by_address[dest].vote_B += claimable;
            return claimable / 2;
        }
        else return 0;
    }

    function concludeVoting() external onlyOwner {
        voting = false;
        total_locked = IReum.balanceOf(address(this));
        winner = tot_vote_A > tot_vote_B ? 1 : 0;
    }

    function getWinner() public view returns(string memory) {
        require(!voting, "Voting still active");
        return winner == 0 ? "A" : "B";
    }

    function withdraw() external {
        require(!voting, "Voting still active");
        voteStruct memory curr = vote_by_address[msg.sender];
        require(!curr.withdrew, "Already withdrew");

        uint256 gains;
        if(winner == 0) {
            gains = curr.vote_A * total_locked / (tot_vote_A + tot_vote_B);
        } else {
            gains = curr.vote_B * total_locked / (tot_vote_A + tot_vote_B);
        }

        IReum.transfer(msg.sender, gains);
    }

    receive () external payable {
        revert();
    }

}