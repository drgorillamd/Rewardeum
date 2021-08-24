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
/// Iteration 0 - general template for unit tests
contract Vault is Ownable, ERC721Holder {

    address main_contract;

    mapping (bytes32 => address) current_asset;
    mapping (bytes32 => uint[]) NFT_tokenID;

    event VaultError(string);

    constructor(address reum) {
        main_contract = reum;
    }

    /// @notice custom claim, only called by the main_contract 
    /// @dev this part should be updated as needed then redeployed
    function claim(uint256 claimable,  address dest, bytes32 ticker) external returns (uint256 claim_consumed) {
        require(msg.sender == main_contract, "Vault: unauthorized access");

        if(ticker == bytes32("REUM")) {
            IERC20 IReum = IERC20(main_contract);
            uint balance = IReum.balanceOf(address(this));
            try IReum.transfer(dest, balance) {
                return 1000;
            } catch Error(string memory _err) {
                emit VaultError(_err);
                return 0;
            }
        }
        else if(ticker == bytes32("NFT_TEST")) {
            IERC721Enumerable INFT = IERC721Enumerable(current_asset["NFT_TEST"]);

            try INFT.safeTransferFrom(address(this), dest, 1) {
                return 1000;
            } catch Error(string memory _err) {
                emit VaultError(_err);
                return 0;
            }
        }
    }

    function addAsset(bytes32 ticker, address asset_adr) external onlyOwner {
        current_asset[bytes32(ticker)] = asset_adr;
    }

    function syncNFTEnum(bytes32 ticker) external {
        IERC721Enumerable INFT = IERC721Enumerable(current_asset[bytes32(ticker)]);
        uint256 num_token = INFT.balanceOf(address(this));
        uint256[] memory _ids = new uint256[](num_token-1);
        for(uint i; i<num_token; i++) _ids[i] = INFT.tokenOfOwnerByIndex(address(this), i);
        NFT_tokenID[bytes32(ticker)] = _ids;
    }

    function syncNFTNonEnum(bytes32 ticker, uint256[] memory _ids) external onlyOwner {
        NFT_tokenID[bytes32(ticker)] = _ids;
    }
//TODO retrieve all, if needed
    receive () external payable {}

}