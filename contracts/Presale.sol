pragma solidity 0.8.0;
// SPDX-License-Identifier: GPL - author: @DrGorilla_md (Tg/Twtr)

/// @author DrGorilla_md
/// @title $REUM - presale and autoliq contract.
/// @notice 3 differents quotas -> whitelisted, "private" (ie any non-whitelisted address) and "reserved" for public listing
/// whitelisted and presale are independent quotas.
/// When presale is over (owner is calling concludeAndAddLiquidity), the liquidity quota is
/// paired with appropriate amount of BNB (if not enough BNB, less token then) -> public price is the constraint
/// + a fixed part is transered to the main token contract as initial reward pool.
/// Claim() is then possible (AFTER the initial liquidity is added).
/// This contract will then remains at least a week, for late claims (it can be then, manually, destruct -> token left
/// are transfered to the dev multisig.

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Reum_presale is Ownable {

  mapping (address => uint256) public amountBought;
  mapping (address => bool) public whiteListed;

  enum status {
    beforeSale,
    ongoingSale,
    postSale
  }

  status public sale_status;

  uint256 public presale_end_ts;
  uint256 public presale_token_per_BNB = 630;  //pre-sale price (630B/1BNB) AKA (630*10**9*10**9)/10**18
  uint256 public whitelist_token_per_BNB = 665;
  uint256 public public_token_per_BNB = 595; //public pancake listing

  uint256 public total_bought;
  uint256 public total_claimed;

  struct track { //use to be uint128, but totalSupply's are growing exponentially...
    uint256 whiteQuota;      //16625 * 10**10 * 10**9; 166.25T whitelist
    uint256 presaleQuota;    //189 * 10**12 * 10**9; 189 presale
    uint256 liquidityQuota;  //229075 * 10**9 * 10**9;  229.075 public
    uint256 sold_in_private; //track the amount bought by non-whitelisted
    uint256 sold_in_whitelist;
  }

  track public Quotas = track(16625 * 10**10 * 10**9, 189 * 10**12 * 10**9, 229075 * 10**9 * 10**9, 0, 0);
  
  IERC20 public token_interface;
  IUniswapV2Router02 router;
  IUniswapV2Pair pair;

  event Buy(address, uint256, uint256);
  event LiquidityTransferred(uint256, uint256);
  event Claimable(address, uint256, uint256);

  modifier beforeSale() {
    require(sale_status == status.beforeSale, "Sale: already started");
    _;
  }

  modifier ongoingSale() {
    require(sale_status == status.ongoingSale, "Sale: already started");
    _;
  }

  modifier postSale() {
    require(sale_status == status.postSale, "Sale: not ended yet");
    _;
  }
  
  /// @dev this contract should be excluded in the main contract
  constructor(address _router, address _token_address) {
      router = IUniswapV2Router02(_router);
      require(router.WETH() != address(0), 'Router error');

      IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

      address pair_adr = factory.getPair(router.WETH(), _token_address);
      pair = IUniswapV2Pair(pair_adr);
      require(pair_adr != address(0), 'Pair error');

      token_interface = IERC20(_token_address);
      sale_status = status.beforeSale;
  }

// -- before sale --

  /// @dev retain capacity to whitelist during the sale (ie too much "zombies" not coming)
  function addWhitelist(address[] calldata _adr) external onlyOwner {
    for(uint256 i=0; i< _adr.length; i++) {
      if(whiteListed[_adr[i]] == false) {
        whiteListed[_adr[i]] = true;
      }
    }
  }

  function isWhitelisted() external view returns (bool){
    return whiteListed[msg.sender];
  }

  function saleStatus() external view returns(uint256) {
    return uint256(sale_status);
  }

// -- Presale launch --

  function startSale() external beforeSale onlyOwner {
    require(token_interface.balanceOf(address(this)) >= Quotas.whiteQuota + Quotas.presaleQuota + Quotas.liquidityQuota, "Presale: not enough token");
    sale_status = status.ongoingSale;
  }

// -- Presale flow --

  /// @dev will revert when quotas are emptied
  function tokenLeftForPrivateSale() public view returns (uint256) {
    require(Quotas.presaleQuota >= Quotas.sold_in_private, "Private sale: No more token to sell");
    unchecked {
      return Quotas.presaleQuota - Quotas.sold_in_private;
    }
  }

  function tokenLeftForWhitelistSale() public view returns (uint256) {
    require(Quotas.whiteQuota >= Quotas.sold_in_whitelist, "Whitelist: No more token to sell");
    unchecked {
      return Quotas.whiteQuota - Quotas.sold_in_whitelist;
    }
  }


  function buy() external payable ongoingSale {
    require(msg.value >= 2 * 10**17, "Sale: Under min amount"); // <0.2 BNB
    require(amountBought[msg.sender] + msg.value <= 2*10**18, "Sale: above max amount"); // >2bnb

    bool whiteListed_adr = whiteListed[msg.sender];
    uint256 amountToken;

    if(whiteListed_adr) {
      amountToken = msg.value * whitelist_token_per_BNB;
      require(amountToken <= tokenLeftForWhitelistSale(), "Sale: No token left in whitelist");
      Quotas.sold_in_whitelist += amountToken;
    }
    else {
      amountToken = msg.value * presale_token_per_BNB;
      require(amountToken <= tokenLeftForPrivateSale(), "Sale: No token left in presale");
      Quotas.sold_in_private += amountToken;
    }

    amountBought[msg.sender] = amountBought[msg.sender] + msg.value;
    total_bought += amountToken;
    emit Claimable(msg.sender, msg.value, amountToken);
  }

  function allowanceLeftInBNB() external view returns (uint256) {
    return 2*10**18 - amountBought[msg.sender];
  }
  
  function amountTokenBought() external view returns (uint256) {
    uint256 amountToken = whiteListed[msg.sender] ? whitelist_token_per_BNB * amountBought[msg.sender] : presale_token_per_BNB * amountBought[msg.sender];
    return amountToken;
  }


// -- post sale --

  function claim() external postSale {
    require(amountBought[msg.sender] > 0, "0 tokens to claim");
    uint256 amountToken = whiteListed[msg.sender] ? whitelist_token_per_BNB * amountBought[msg.sender] : presale_token_per_BNB * amountBought[msg.sender];
    amountBought[msg.sender] = 0;
    total_claimed += amountToken;
    token_interface.transfer(msg.sender, amountToken);
  }

  /// @dev convert BNB received and token left in pool liquidity. LP send to owner.
  ///     Uni Router handles both scenario : existing and non-existing pair
  /// not in postSale scope to avoid having claim and third-party liq before calling it
  /// @param portion_for_reward_in_percent % of BNB transfered to the token contract as initial reward pool
  /// @param emergency_slippage modify the token amount desired in addLiquidity
  /// @param correcting_ratio bool to trigger the "anti-pool-spam" mechanism (rebalance and atomically sync)
  /// @param left_over_address dest address for leftover BNB (left over token are only withdrawable after a week, for late claimers)
  function concludeAndAddLiquidity(uint256 portion_for_reward_in_percent, uint256 emergency_slippage, bool correcting_ratio, address left_over_address) external onlyOwner {

    address token = payable(address(token_interface));
    uint256 to_transfer = address(this).balance * portion_for_reward_in_percent / 100;
    (bool success,) = token.call{value: to_transfer}(new bytes(0));
    require(success, 'TransferHelper: ETH_TRANSFER_FAILED');

    if(address(pair).balance > 0 && correcting_ratio) { // pair contract spammed with BNB ?
      uint256 to_add = address(pair).balance * public_token_per_BNB;
      token_interface.transfer(address(pair), to_add);
      pair.sync();
    }

    uint256 balance_BNB = address(this).balance;
    uint256 balance_token = token_interface.balanceOf(address(this));

    if(balance_token > Quotas.liquidityQuota) balance_token = Quotas.liquidityQuota; //public capped at Quotas.liquidityQuota

    if(balance_token / balance_BNB >= public_token_per_BNB) { // too much token for BNB
        balance_token = public_token_per_BNB * balance_BNB;
      }
      else { // too much BNB for token left
        balance_BNB = balance_token / public_token_per_BNB;
      }
    
    token_interface.approve(address(router), balance_token);
    router.addLiquidityETH{value: balance_BNB}(
        address(token_interface),
        balance_token,
        balance_token - (balance_token * emergency_slippage / 100),
        balance_BNB,
        address(0x000000000000000000000000000000000000dEaD), //liquidity tokens are burned
        block.timestamp
    );

    sale_status = status.postSale;
    presale_end_ts = block.timestamp;
    
    //safeTransfer
    address to = payable(left_over_address);  //multisig (should be 0)
    (bool success2,) = to.call{value: address(this).balance}(new bytes(0));
    require(success2, 'TransferHelper: ETH_TRANSFER_FAILED');

    emit LiquidityTransferred(balance_BNB, balance_token);
      
  }

/// @dev wait min 1 week after presale ending, for "late claimers", before destroying the
/// contract and emptying it.
  function finalClosure(address leftover_dest) external onlyOwner {
    require(block.timestamp >= presale_end_ts + 604800, "finalClosure: grace period");

    if(token_interface.balanceOf(address(this)) != 0) {
      token_interface.transfer(leftover_dest, token_interface.balanceOf(address(this)));
    }

    selfdestruct(payable(leftover_dest));
  }

  fallback () external payable {
    revert("Don't you dare");
  }

}
