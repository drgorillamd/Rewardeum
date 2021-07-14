pragma solidity 0.8.0;
// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

/* $iBNB - presale and autoliq contract.
*
* 3 differents quotas -> whitelisted, "private" (ie any non-whitelisted address) and public
* whitelisted and presale are independent.
* When presale is over (owner is calling concludeAndAddLiquidity), the liquidity quota is
* paired with appropriate amount of BNB (if not enough BNB, less token then) -> public price is the constraint
* Claim() is then possible (AFTER the initial liquidity).
* This contract will then remains at least a week, for late claims (it can be then, manually, destruct -> token and BNB left
* are transfered to the multisig.
*
* Feel free to reach out for tech chat Tg/CT: @ DrGorilla_md
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract iBNB_presale is Ownable {

using SafeMath for uint256;
using SafeMath for uint128;

// -- variables --

  mapping (address => uint256) amountBought;
  mapping (address => bool) public whiteListed;

  enum status {
    beforeSale,
    ongoingSale,
    postSale
  }

  status public sale_status;

  uint256 public presale_end_ts;
  uint256 public presale_token_per_BNB = 500;  //pre-sale price (500b/1BNB) AKA (500*10**9*10**9)/10**18 - thx Jasper
  uint256 public public_token_per_BNB = 400; //public pancake listing (400b/1BNB)

  struct track {
    uint128 whiteQuota;      //80 * 10**12 * 10**9; 80T whitelist
    uint128 presaleQuota;    //180 * 10**12 * 10**9; 180T presale
    uint128 liquidityQuota;  //327 * 10**12 * 10**9;  338T public
    uint128 sold_in_private; //track the amount bought by non-whitelisted
    uint128 sold_in_whitelist;
  }

  track private Quotas = track(80 * 10**12 * 10**9, 180 * 10**12 * 10**9, 327 * 10**12 * 10**9, 0, 0);
  
  ERC20 public iBNB_token;
  IUniswapV2Router02 router;

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
  }    //@dev set circuit_breaker to true for the duration of the sale
  constructor(address _router, address _ibnb_address) {
      router = IUniswapV2Router02(_router);
      require(router.WETH() != address(0), 'Router error');
      iBNB_token = ERC20(_ibnb_address);
      sale_status = status.beforeSale;
  }

// -- before sale --

  //@dev retain whitelisting capacity during the sale (ie too much "zombies" not coming)
  // allowance max is 2BNB, +10**18 to flag whitelisted accounts (ie non-whitelisted == 0)
  // in claim() 
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
    require(iBNB_token.balanceOf(address(this)) >= Quotas.whiteQuota.add(Quotas.presaleQuota).add(Quotas.liquidityQuota), "Presale: not enough iBNB");
    sale_status = status.ongoingSale;
  }

// -- Presale flow --

  //@dev contract starts with presale+public
  //     will revert when quotas are emptied
  function tokenLeftForPrivateSale() public view returns (uint256) {
    return Quotas.presaleQuota.sub(Quotas.sold_in_private, "Private sale: No more token to sell");
  }

  function tokenLeftForWhitelistSale() public view returns (uint256) {
    return Quotas.whiteQuota.sub(Quotas.sold_in_whitelist, "Whitelist: No more token to sell");
  }


  function buy() external payable ongoingSale {
    require(msg.value >= 2 * 10**17, "Sale: Under min amount"); // <0.2 BNB
    require(amountBought[msg.sender].add(msg.value) <= 2*10**18, "Sale: above max amount"); // >2bnb

    uint128 amountToken = uint128(msg.value.mul(presale_token_per_BNB));

    require(amountToken <= tokenLeftForPrivateSale() || (whiteListed[msg.sender] && amountToken <= tokenLeftForWhitelistSale()), "Sale: Not enough token left");

    if(whiteListed[msg.sender]) {
      Quotas.sold_in_whitelist += amountToken;
    } else {
      Quotas.sold_in_private += amountToken;
    }

    amountBought[msg.sender] = amountBought[msg.sender].add(msg.value);
    emit Claimable(msg.sender, msg.value, amountToken);
  }

  function allowanceLeftInBNB() external view returns (uint256) {
    return 2*10**18 - amountBought[msg.sender];
  }
  
  function amountTokenBought() external view returns (uint256) {
    return amountBought[msg.sender].mul(presale_token_per_BNB);
  }


// -- post sale --

  function claim() external postSale {
    require(amountBought[msg.sender] > 0, "0 tokens to claim");
    uint256 amountToken = presale_token_per_BNB.mul(amountBought[msg.sender]);
    amountBought[msg.sender] = 0;
    iBNB_token.transfer(msg.sender, amountToken);
  }

  //@dev convert BNB received and token left in pool liquidity. LP send to owner.
  //     Uni Router handles both scenario : existing and non-existing pair
  //     /!\ will revert if < 1BNB in contract
  // not in postSale scope to avoid having claim and third-party liq before calling it
  function concludeAndAddLiquidity() external onlyOwner {
    uint256 balance_BNB = address(this).balance;
    uint256 balance_token = iBNB_token.balanceOf(address(this));

    if(balance_token > Quotas.liquidityQuota) balance_token = Quotas.liquidityQuota; //public capped at Quotas.liquidityQuota

    if(balance_token.div(balance_BNB) >= public_token_per_BNB) { // too much token for BNB
        balance_token = public_token_per_BNB.mul(balance_BNB);
      }
      else { // too much BNB for token left
        balance_BNB = balance_token.div(public_token_per_BNB);
      }

    iBNB_token.approve(address(router), balance_token);
    router.addLiquidityETH{value: balance_BNB}(
        address(iBNB_token),
        balance_token,
        balance_token,
        balance_BNB,
        address(0x000000000000000000000000000000000000dEaD), //liquidity tokens are burned
        block.timestamp
    );

    sale_status = status.postSale;
    presale_end_ts = block.timestamp;
    
    //safeTransfer
    address to = payable(0x0DCDfcEaA329fDeb9025cdAED5c91B09D1417E93);  //multisig
    (bool success,) = to.call{value: address(this).balance}(new bytes(0));
    require(success, 'TransferHelper: ETH_TRANSFER_FAILED');

    emit LiquidityTransferred(balance_BNB, balance_token);
      
  }

//@dev wait min 1 week after presale ending, for "late claimers", before destroying the
//contract and emptying it.
  function finalClosure() external onlyOwner {
    require(block.timestamp >= presale_end_ts + 604800, "finalClosure: grace period");

    if(iBNB_token.balanceOf(address(this)) != 0) {
      iBNB_token.transfer(0x0DCDfcEaA329fDeb9025cdAED5c91B09D1417E93, iBNB_token.balanceOf(address(this))); //dev multisig
    }

    selfdestruct(payable(0x0DCDfcEaA329fDeb9025cdAED5c91B09D1417E93));  //dev multisig
  }

  fallback () external payable {
    revert();
  }

}
