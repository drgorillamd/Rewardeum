// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract Vault is Ownable, ERC721Holder {
    address main_contract;
    mapping (string => address) current_asset;

    event VaultError(string);

    constructor(address reum) {
        main_contract = reum;
    }

    function claim(string memory ticker, address dest) external returns (bool) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

        if(keccak256(abi.encodePacked(ticker)) == keccak256(abi.encodePacked("REUM"))) {
            IERC20 IReum = IERC20(main_contract);
            uint balance = IReum.balanceOf(address(this));
            try IReum.transfer(dest, balance) {
                return true;
            } catch Error(string memory _err) {
                emit VaultError(_err);
                return false;
            }
        }
        else if(keccak256(abi.encodePacked(ticker)) == keccak256(abi.encodePacked("NFT_TEST"))) {
            IERC721 INFT = IERC721(current_asset["NFT_TEST"]);
            try INFT.safeTransferFrom(address(this), dest, 1) {
                return true;
            } catch Error(string memory _err) {
                emit VaultError(_err);
                return false;
            }
        }
    }

    function addAsset(string memory ticker, address asset_adr) external onlyOwner {
        current_asset[ticker] = asset_adr;
    }

    receive () external payable {}

}