// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


/// @title Rewardeum - Main contract
/// @author DrGorilla_md (Twtr/Tg)
/// @notice ERC20 compliant token with taxes on transfer, funding a double reward pool system:
/// - Reward pool
/// - Reserve
/// Every user can claim every 24h a reward, based on the share of the total supply owned. The token
/// claimed is either BNB or any other available token (from a curated list).
/// An additional incentive mechanism (the "Vault") offer extra reward on chosen claimable tokens.
/// @dev this contract is custodial for BNB and $reum (swapped for BNB in batches), custom token 
/// are swapped as needed. Main contract act as a proxy for the vault (via IVault) which is redeployed
/// for new offers. Tickers are stored in bytes32 for gas optim (frontend integration via web3.utils.hexToAscii and asciiToHex)

interface IVault {
  function claim(uint256 claimable, address dest, bytes32 ticker) external returns (uint256 claim_consumed);
}

/// @dev part of erc20 but not part of erc20 ...
interface IDec {
  function decimals() external view returns (uint8);
}

contract Rewardeum is IERC20 {

  struct past_tx {
    uint256 cum_sell;
    uint256 last_sell;
    uint256 reward_buffer;
    uint256 last_claim;
  }

  struct smartpool_struct {
    uint256 BNB_reward;
    uint256 BNB_reserve;
    uint256 BNB_prev_reward;
    uint256 token_reserve;
  }

  struct prop_balances {
    uint256 reward_pool;
    uint256 liquidity_pool;
  }

  struct taxesRates {
    uint8 dev;
    uint8 market;
    uint8 balancer;
    uint8 reserve;
  }

  mapping (address => uint256) private _balances;
  mapping (address => past_tx) private _last_tx;
  mapping (address => mapping (address => uint256)) private _allowances;
  mapping (address => bool) private excluded;
  mapping (address => bool) public isOwner;
  
// ---- custom claim ----
  mapping (bytes32 => address) public available_tokens;
  mapping (bytes32 => uint256) public custom_claimed;
  mapping (bytes32 => address) public combined_offer;
  mapping (address => uint256) public min_received; // % min received or 100-max slippage

// ---- tokenomic ----
  uint private _decimals = 9;
  uint private _totalSupply = 10**15 * 10**_decimals;
  uint8[4] public selling_taxes_rates = [2, 5, 10, 20];
  uint16[3] public selling_taxes_tranches = [200, 500, 1000]; // % and div by 10000 0.012% -0.025% -(...)

// ---- balancer ----
  uint private pcs_pool_to_circ_ratio = 10;
  uint public swap_for_liquidity_threshold = 10**13 * 10**_decimals; //1%
  uint public swap_for_reward_threshold = 10**13 * 10**_decimals;
  uint public swap_for_reserve_threshold = 10**13 * 10**_decimals;

// ---- smartpool ----
  uint public last_smartpool_check;
  uint public smart_pool_freq = 1 days;
  uint public excess_rate = 200;
  uint public minor_fill = 2;
  uint public resplenish_factor = 100;
  uint public spike_threshold = 120;
  uint public shock_absorber = 0;

// ---- claim ----
  uint claim_periodicity = 1 days;
  uint private claim_ratio = 80;
  uint public gas_flat_fee = 0.000361 ether;
  uint public total_claimed;
  uint8[5] public claiming_taxes_rates = [2, 5, 10, 20, 30];
  uint128[2] public gas_waiver_limits = [0.0001 ether, 0.0005 ether];

  bool public circuit_breaker;
  bool private inSwapBool;

  string private _name = "Rewardeum";
  string private _symbol = "REUM";

  bytes32[] public tickers_claimable;
  bytes32[] public current_offers;

  address public LP_recipient;
  address public devWallet;
  address public mktWallet;
  address private WETH;

  IVault public main_vault;
  IUniswapV2Pair public pair;
  IUniswapV2Router02 private router;

  prop_balances private balancer_balances;
  smartpool_struct public smart_pool_balances;
  taxesRates public taxes = taxesRates({dev: 1, market: 1, balancer: 5, reserve: 8});

  event TaxRatesChanged();
  event SwapForBNB(string status);
  event SwapForCustom(string status);
  event Claimed(bytes32 ticker, uint256 claimable, uint256 tax, bool gas_waiver);
  event BalancerPools(uint256 reward_liq_pool, uint256 reward_token_pool);
  event RewardTaxChanged();
  event AddLiq(string status);
  event BalancerReset(uint256 new_reward_token_pool, uint256 new_reward_liq_pool);
  event Smartpool(uint256 reward, uint256 reserve, uint256 prev_reward);
  event SmartpoolOverride(uint256 new_reward, uint256 new_reserve);
  event AddClaimableToken(bytes32 ticker, address token);
  event RemoveClaimableToken(bytes32 ticker);
  event TransferBNB(address, uint256);

  modifier inSwap {
    inSwapBool = true;
    _;
    inSwapBool = false;
  }

  modifier onlyOwner {
    require(isOwner[msg.sender], "Ownable: caller is not an owner");
    _;
  }

  constructor (address _router) {

    router = IUniswapV2Router02(_router);
    WETH = router.WETH();
    IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
    pair = IUniswapV2Pair(factory.createPair(address(this), router.WETH()));

    LP_recipient = address(0x000000000000000000000000000000000000dEaD); //LP token: burn
    devWallet = address(0x000000000000000000000000000000000000dEaD);
    mktWallet = address(0x000000000000000000000000000000000000dEaD);

    excluded[msg.sender] = true;
    excluded[address(this)] = true;
    excluded[devWallet] = true;
    excluded[mktWallet] = true;

    isOwner[msg.sender] = true;

    circuit_breaker = true; //ERC20 behavior by default/presale

// -- standard custom claims --
    available_tokens[0x5245554d00000000000000000000000000000000000000000000000000000000] = address(this); //"REUM"
    min_received[address(this)] = 83;
    tickers_claimable.push("REUM"); //will get stored as bytes32 too

    available_tokens[0x57424e4200000000000000000000000000000000000000000000000000000000] = address(WETH);
    min_received[WETH] = 95;
    tickers_claimable.push("WBNB");

    available_tokens[0x4254434200000000000000000000000000000000000000000000000000000000] = address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
    min_received[address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c)] = 95;
    tickers_claimable.push("BTCB");

    available_tokens[0x4554480000000000000000000000000000000000000000000000000000000000] = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    min_received[address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8)] = 95;
    tickers_claimable.push("ETH");

    available_tokens[0x4255534400000000000000000000000000000000000000000000000000000000] = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    min_received[address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)] = 95;
    tickers_claimable.push("BUSD");

    available_tokens[0x5553445400000000000000000000000000000000000000000000000000000000] = address(0x55d398326f99059fF775485246999027B3197955);
    min_received[address(0x55d398326f99059fF775485246999027B3197955)] = 95;
    tickers_claimable.push("USDT");

// -- limited offer at launch --
    available_tokens[0x4144410000000000000000000000000000000000000000000000000000000000] = address(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47);
    min_received[address(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47)] = 95;
    tickers_claimable.push("ADA");

    available_tokens[0x43616b6500000000000000000000000000000000000000000000000000000000] = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    min_received[address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82)] = 95;
    tickers_claimable.push("Cake");

    available_tokens[0x5852500000000000000000000000000000000000000000000000000000000000] = address(0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE);
    min_received[address(0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE)] = 95;
    tickers_claimable.push("XRP");

    available_tokens[0x444f540000000000000000000000000000000000000000000000000000000000] = address(0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402);
    min_received[address(0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402)] = 95;
    tickers_claimable.push("DOT");

    available_tokens[0x444f474500000000000000000000000000000000000000000000000000000000] = address(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);
    min_received[address(0xbA2aE424d960c26247Dd6c32edC70B295c744C43)] = 95;
    tickers_claimable.push("DOGE");

    _balances[msg.sender] = _totalSupply;
    emit Transfer(address(0), msg.sender, _totalSupply);
  }

  function decimals() public view returns (uint256) {
        return _decimals;
  }
  function name() public view returns (string memory) {
      return _name;
  }
  function symbol() public view returns (string memory) {
      return _symbol;
  }
  function totalSupply() public view virtual override returns (uint256) {
      return _totalSupply;
  }
  function balanceOf(address account) public view virtual override returns (uint256) {
      return _balances[account];
  }
  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
      _transfer(msg.sender, recipient, amount);
      return true;
  }
  function allowance(address owner, address spender) public view virtual override returns (uint256) {
      return _allowances[owner][spender];
  }
  function approve(address spender, uint256 amount) public virtual override returns (bool) {
      _approve(msg.sender, spender, amount);
      return true;
  }
  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
      _transfer(sender, recipient, amount);

      uint256 currentAllowance = _allowances[sender][msg.sender];
      require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
      unchecked {
        _approve(sender, msg.sender, currentAllowance - amount);
      }
      return true;
  }
  function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
      _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
      return true;
  }
  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
      uint256 currentAllowance = _allowances[msg.sender][spender];
      require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
      unchecked {
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
      }
      return true;
  }
  function _approve(address owner, address spender, uint256 amount) internal virtual {
      require(owner != address(0), "ERC20: approve from the zero address");
      require(spender != address(0), "ERC20: approve to the zero address");

      _allowances[owner][spender] = amount;
      emit Approval(owner, spender, amount);
  }


  function _transfer(address sender, address recipient, uint256 amount) internal virtual {
      require(sender != address(0), "ERC20: transfer from the zero address");
      
      uint256 senderBalance = _balances[sender];
      require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

      uint256 sell_tax;
      uint256 dev_tax;
      uint256 mkt_tax;
      uint256 balancer_amount;
      uint256 contribution;
      

      if(!inSwapBool && excluded[sender] == false && excluded[recipient] == false && circuit_breaker == false) {
      
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves(); // returns reserve0, reserve1, timestamp last tx
        if(address(this) != pair.token0()) { // 0 := iBNB
          (_reserve0, _reserve1) = (_reserve1, _reserve0);
        }
        
      // ----  Sell tax & timestamp update ----
        if(recipient == address(pair)) {
          sell_tax = sellingTax(sender, amount, _reserve0); //will update the balancer/timestamps too
        }

      // ----  Smart pool funding & check ----
        contribution = amount* taxes.reserve / 100;
        smart_pool_balances.token_reserve += contribution;
        if(last_smartpool_check < block.timestamp + smart_pool_freq) smartPoolCheck();
        
      // ------ "flexible"/dev&marketing taxes -------
        dev_tax = amount  * taxes.dev / 100;
        mkt_tax = amount * taxes.market / 100;

      // ------ balancer tax  ------
        balancer_amount = amount * taxes.balancer / 100;
        balancer(balancer_amount, _reserve0);

      // ----- reward buffer -----
        if(_balances[recipient] != 0) {
          _last_tx[recipient].reward_buffer += amount - sell_tax - dev_tax - mkt_tax - balancer_amount - contribution;
        } else {
          _last_tx[recipient].reward_buffer = 0;
        }

      //every extra token are collected into address(this), the balancer then split them
      //between pool and reward, using the appropriate struct
        _balances[address(this)] += sell_tax + balancer_amount + contribution;
        _balances[devWallet] += dev_tax;
        _balances[mktWallet] += mkt_tax;

      }
      //else, by default:
      //  sell_tax = 0;
      //  dev_tax = 0;
      //  balancer_amount = 0;
      //  contribution to smart pool = 0;

      if(_balances[recipient] == 0) _last_tx[recipient].last_claim = block.timestamp;

      _balances[sender] = senderBalance - amount;
      _balances[recipient] += amount - sell_tax - dev_tax - mkt_tax - balancer_amount - contribution;
      
      emit Transfer(sender, recipient, amount- sell_tax - dev_tax - mkt_tax - balancer_amount - contribution);
      emit Transfer(sender, address(this), sell_tax);
      emit Transfer(sender, address(this), balancer_amount);
      emit Transfer(sender, devWallet, dev_tax);
      emit Transfer(sender, mktWallet, mkt_tax);
  }

  /// @dev take a selling tax if transfer from a non-excluded address or from the pair contract exceed
  /// the thresholds defined in selling_taxes_thresholds on a 24h floating window
  function sellingTax(address sender, uint256 amount, uint256 pool_balance) internal returns(uint256 sell_tax) {

    if(block.timestamp > _last_tx[sender].last_sell + 1 days) {
      _last_tx[sender].cum_sell = 0; // a.k.a The Virgin

    } else {
      uint16[3] memory _tax_tranches = selling_taxes_tranches;

      uint256 new_cum_sum = amount+ _last_tx[sender].cum_sell;

      if(new_cum_sum > pool_balance * _tax_tranches[2] / 10**4) sell_tax = amount * selling_taxes_rates[3] / 100;
      else if(new_cum_sum > pool_balance * _tax_tranches[1] / 10**4) sell_tax = amount * selling_taxes_rates[2] / 100;
      else if(new_cum_sum > pool_balance * _tax_tranches[0] / 10**4) sell_tax = amount * selling_taxes_rates[1] / 100;
      else sell_tax = amount * selling_taxes_rates[0] / 100;
    }

    _last_tx[sender].cum_sell = _last_tx[sender].cum_sell + amount;
    _last_tx[sender].last_sell = block.timestamp;

    smart_pool_balances.token_reserve += sell_tax; //sell tax goes in the dynamic reward pool

    return sell_tax;
  }


  /// @dev take the balancer taxe as input, split it between reward and liq subpools
  ///    according to pool condition -> circ-pool/circ supply closer to one implies
  ///    priority to the reward pool. Threshold for swap checks in elif to avoid charging multiple swap on one transfer.
  /// @param amount new amount assigned to the balancer
  /// @param pool_balance reserve amount returned from the pair contract
  function balancer(uint256 amount, uint256 pool_balance) internal {

      address DEAD = address(0x000000000000000000000000000000000000dEaD);
      uint256 unwght_circ_supply = totalSupply() - _balances[DEAD];

      uint256 circ_supply = (pool_balance < unwght_circ_supply * pcs_pool_to_circ_ratio / 100) ? unwght_circ_supply * pcs_pool_to_circ_ratio / 100 : pool_balance;

      balancer_balances.liquidity_pool += ((amount * (circ_supply - pool_balance)) * 10**9 / circ_supply) / 10**9;
      balancer_balances.reward_pool += ((amount * pool_balance) * 10**9 / circ_supply) / 10**9;

      prop_balances memory _balancer_balances = balancer_balances;

      if(_balancer_balances.reward_pool >= swap_for_reward_threshold) {
        uint256 BNB_balance_before = address(this).balance;
        uint256 token_out = swapForBNB(swap_for_reward_threshold, address(this)); //returns 0 if fail
        balancer_balances.reward_pool -= token_out; 
        smart_pool_balances.BNB_reward += address(this).balance - BNB_balance_before;
      }

      else if(smart_pool_balances.token_reserve >= swap_for_reserve_threshold) {
        uint256 BNB_balance_before = address(this).balance;
        uint256 token_out = swapForBNB(swap_for_reserve_threshold, address(this)); //returns 0 if fail
        smart_pool_balances.token_reserve -= token_out; 
        smart_pool_balances.BNB_reserve += address(this).balance - BNB_balance_before;
      }

      else if(_balancer_balances.liquidity_pool >= swap_for_liquidity_threshold) {
        uint256 token_out = addLiquidity(swap_for_liquidity_threshold); //returns 0 if fail
        balancer_balances.liquidity_pool -= token_out;
      }

      emit BalancerPools(_balancer_balances.liquidity_pool, _balancer_balances.reward_pool);
  }

  /// @dev when triggered, will swap and provide liquidity
  /// BNBfromSwap being the difference between before and after the swap, slippage
  /// will result in extra-BNB for the reward pool (free money for the guys:)
  function addLiquidity(uint256 token_amount) internal inSwap returns (uint256) {
    uint256 smart_pool_balance = address(this).balance;

    address[] memory route = new address[](2);
    route[0] = address(this);
    route[1] = router.WETH();

    if(allowance(address(this), address(router)) < token_amount) {
      _allowances[address(this)][address(router)] = ~uint256(0);
      emit Approval(address(this), address(router), ~uint256(0));
    }
    
    //odd numbers management -> half is smaller than amount.min(half)
    uint256 half = token_amount / 2;
    
    try router.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, route, address(this), block.timestamp) {
      uint256 BNB_from_Swap = address(this).balance - smart_pool_balance;

        try router.addLiquidityETH{value: BNB_from_Swap}(address(this), half, 0, 0, LP_recipient, block.timestamp) {
          emit AddLiq("addLiq: ok");
          return (token_amount / 2) * 2;
        } catch {
          emit AddLiq("addLiq:liq fail");
          return 0;
        }

    } catch {
      emit AddLiq("addLiq:swap fail");
      return 0;
    }
  }

  /// @notice compute and return the available reward of the user, based on his token holding and the reward pool balance
  /// @return the tupple (net reward, tax paid, eligible for a "gas waiver")
  function computeReward() public view returns(uint256, uint256 tax_to_pay, bool gas_waiver) {

    past_tx memory sender_last_tx = _last_tx[msg.sender];

    //one claim max every 24h
    if (sender_last_tx.last_claim + claim_periodicity > block.timestamp) return (0, 0, false);

    uint256 balance_without_buffer = sender_last_tx.reward_buffer >= _balances[msg.sender] ? 0 : _balances[msg.sender] - sender_last_tx.reward_buffer;

    // no more linear increase/ "on-off" only
    uint256 _nom = balance_without_buffer * smart_pool_balances.BNB_reward * claim_ratio;
    uint256 _denom = totalSupply() * 100; //100 from claim ratio
    uint256 gross_reward_in_BNB = _nom / _denom;

    tax_to_pay = taxOnClaim(gross_reward_in_BNB);
    if(tax_to_pay == gas_flat_fee) return(gross_reward_in_BNB + tax_to_pay, 0, true);
    return (gross_reward_in_BNB - tax_to_pay, tax_to_pay, false);
  }

  /// @dev Compute the tax on claimed reward - labelled in BNB
  function taxOnClaim(uint256 amount) internal view returns(uint256 tax){
    if(amount <= gas_waiver_limits[1] && amount >= gas_waiver_limits[0]) return gas_flat_fee;

    if(amount > 2 ether) return amount * claiming_taxes_rates[4] / 100;
    if(amount > 1.50 ether) return amount * claiming_taxes_rates[3] / 100;
    if(amount > 1 ether) return amount * claiming_taxes_rates[2] / 100;
    if(amount > 0.5 ether) return amount * claiming_taxes_rates[1] / 100;
    if(amount > 0.01 ether) return amount * claiming_taxes_rates[0] / 100;
    //if <0.01
    return 0;
  }

  /// @dev tax goes to the smartpool reserve
  function claimReward(bytes32 ticker) external {
    (uint256 claimable, uint256 tax, bool gas_waiver) = computeReward();
    require(claimable > 0, "Claim: 0");

    address dest_token = available_tokens[ticker];
    require(dest_token != address(0), "Claim: invalid dest token");

    smart_pool_balances.BNB_reward -= (claimable+tax);
    smart_pool_balances.BNB_reserve += tax;

    _last_tx[msg.sender].reward_buffer = 0;
    _last_tx[msg.sender].last_claim = block.timestamp;

    custom_claimed[ticker]++;
    total_claimed += claimable;
              
    if(last_smartpool_check < block.timestamp + smart_pool_freq) smartPoolCheck();

    if(dest_token == WETH) safeTransferETH(msg.sender, claimable);
    else if(dest_token == address(main_vault)) {
      uint256 claim_consumed = main_vault.claim(claimable, msg.sender, ticker); //multiple bonuses -> same vault address, ticker passed to get the correct one in vault contract
      if(combined_offer[ticker] != address(0)) {
        swapForCustom(claimable - claim_consumed, msg.sender, combined_offer[ticker]);
      }
    }
    else swapForCustom(claimable, msg.sender, dest_token);

    emit Claimed(ticker, claimable, tax, gas_waiver);
  }

  function smartPoolCheck() internal {
    smartpool_struct memory _smart_pool_bal = smart_pool_balances;

    if(_smart_pool_bal.BNB_reserve > _smart_pool_bal.BNB_reward * excess_rate / 100) {
      smart_pool_balances.BNB_reward += _smart_pool_bal.BNB_reserve * minor_fill / 100;
      smart_pool_balances.BNB_reserve -= _smart_pool_bal.BNB_reserve * minor_fill / 100;
    }

    if(_smart_pool_bal.BNB_reward <= _smart_pool_bal.BNB_prev_reward) {
      uint256 delta_reward = _smart_pool_bal.BNB_prev_reward - _smart_pool_bal.BNB_reward;
      if (_smart_pool_bal.BNB_reserve >= delta_reward) {
        smart_pool_balances.BNB_reward += delta_reward * resplenish_factor / 100;
        smart_pool_balances.BNB_reserve -= delta_reward * resplenish_factor / 100;
      }
    }
    if(_smart_pool_bal.BNB_reward > _smart_pool_bal.BNB_prev_reward * spike_threshold / 100) {
      uint256 delta_reward = _smart_pool_bal.BNB_reward - _smart_pool_bal.BNB_prev_reward;
      smart_pool_balances.BNB_reward -= delta_reward * shock_absorber / 100;
      smart_pool_balances.BNB_reserve += delta_reward * shock_absorber / 100;
    }
    
    smart_pool_balances.BNB_prev_reward = _smart_pool_bal.BNB_reward;
    last_smartpool_check = block.timestamp;

    emit Smartpool(smart_pool_balances.BNB_reward, smart_pool_balances.BNB_reserve, smart_pool_balances.BNB_prev_reward);

  }

  function swapForBNB(uint256 token_amount, address receiver) internal inSwap returns (uint256) {
    address[] memory route = new address[](2);
    route[0] = address(this);
    route[1] = WETH;

    if(allowance(address(this), address(router)) < token_amount) {
      _allowances[address(this)][address(router)] = ~uint256(0);
      emit Approval(address(this), address(router), ~uint256(0));
    }

    uint256 theo_amount_received;
    try router.getAmountsOut(token_amount, route) returns (uint256[] memory out) {
      theo_amount_received = out[1];
    }
    catch Error(string memory _err) {
      revert(_err);
    }

    uint256 min_to_receive = theo_amount_received * min_received[route[1]] / 100;

    try router.swapExactTokensForETHSupportingFeeOnTransferTokens(token_amount, min_to_receive, route, receiver, block.timestamp) {
      emit SwapForBNB("Swap success");
      return token_amount;
    }
    catch Error(string memory _err) {
      emit SwapForBNB(_err);
      return 0;
    }
  }

  function swapForCustom(uint256 amount, address receiver, address dest_token) internal inSwap returns (uint256) {
    address wbnb = WETH;

    if(dest_token == wbnb) {
      return swapForBNB(amount, receiver);
    } else {
      address[] memory route = new address[](2);
      route[0] = wbnb;
      route[1] = dest_token;

      uint256 bal_before = IERC20(dest_token).balanceOf(receiver);
      uint256 theo_amount_received;
      try router.getAmountsOut(amount, route) returns (uint256[] memory out) {
        theo_amount_received = out[1];
      }
      catch Error(string memory _err) {
        revert(_err);
      }

      uint256 min_to_receive = theo_amount_received * min_received[dest_token] / 100;

      try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(min_to_receive, route, receiver, block.timestamp) {
        emit SwapForCustom("SwapForToken: success");
        uint256 received = IERC20(dest_token).balanceOf(receiver) - bal_before;
        return received;
      } catch Error(string memory _err) {
        revert(_err);
      }
    }
  }

  /// @notice Check if invalid token listed as custom claim
  /// @dev validate all custom addresses by using symbol() from ierc20
  function validateCustomTickers() external view returns (string memory) {
    for(uint i = 0; i < tickers_claimable.length; i++) {
      if(available_tokens[tickers_claimable[i]] != address(main_vault) &&
        keccak256(abi.encodePacked(ERC20(available_tokens[tickers_claimable[i]]).symbol()))
        != keccak256(abi.encodePacked(bytes32ToString(tickers_claimable[i]))))
        return(bytes32ToString(tickers_claimable[i]));
    }
    return "Validate: passed";
  }

  function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
    uint8 i = 0;
    while(i < 32 && _bytes32[i] != 0) {
        i++;
    }
    bytes memory bytesArray = new bytes(i);
    for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
        bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
  }

  function safeTransferETH(address to, uint value) internal {
      (bool success,) = payable(to).call{value: value}(new bytes(0));
      require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
      emit TransferBNB(to, value);
  }

  /// @dev fallback in order to receive BNB from swapToBNB
  receive () external payable {}

// ------------- Indiv addresses management -----------------

  function excludeFromTaxes(address adr) external onlyOwner {
    require(!excluded[adr], "already excluded");
    excluded[adr] = true;
  }

  function includeInTaxes(address adr) external onlyOwner {
    require(excluded[adr], "already taxed");
    excluded[adr] = false;
  }

  function isExcluded(address adr) external view returns (bool){
    return excluded[adr];
  }

  function lastTxStatus(address adr) external view returns (past_tx memory) {
    return _last_tx[adr];
  }

// ---------- In case of emergency, break the glass -------------

  /// @dev will bypass all the taxes and act as erc20.
  ///     pools & balancer balances will remain untouched
  function setCircuitBreaker(bool status) external onlyOwner {
    circuit_breaker = status;
  }

  /// @notice if token accumulated in contract, trigger a swap of all of them
  function forceSwapForReward() external onlyOwner {
    uint256 BNB_balance_before = address(this).balance;
    uint256 token_out = swapForBNB(balancer_balances.reward_pool, address(this)); //returns 0 if fail
    balancer_balances.reward_pool -= token_out; 
    smart_pool_balances.BNB_reward += address(this).balance - BNB_balance_before;
  }

  function forceSmartpoolCheck() external onlyOwner {
    smartPoolCheck();
  }

  /// @dev set the reward (BNB) pool balance, rest of the contract's balance is the reserve
  /// will mostly (hopefully) be used only on first cycle
  function smartpoolOverride(uint256 reward) external onlyOwner {
    require(address(this).balance >= reward, "SPOverride: inf to contract balance");
    smart_pool_balances.BNB_reserve = address(this).balance - reward;
    smart_pool_balances.BNB_reward = reward;
    emit SmartpoolOverride(reward, address(this).balance - reward);
  }

  function resetBalancer() external onlyOwner {
    uint256 _contract_balance = _balances[address(this)];
    balancer_balances.reward_pool = _contract_balance / 2;
    balancer_balances.liquidity_pool = _contract_balance / 2;
    emit BalancerReset(balancer_balances.reward_pool, balancer_balances.liquidity_pool);
  }

//  --------------  setters ---------------------

  /// @dev Vaults are deployed on a per-use basis/this is a proxy to them
  function setVault(address new_vault) external onlyOwner {
    main_vault = IVault(new_vault);
  }

  /// @notice add custom token to claim
  /// @param new_token address of the custom claim token contract
  /// @param ticker in bytes32
  /// @param _min_received_percents to fix the max slippage
  function addClaimable(address new_token, bytes32 ticker, uint256 _min_received_percents) external onlyOwner {
    available_tokens[ticker] = new_token;
    tickers_claimable.push(ticker);
    min_received[new_token] = _min_received_percents;
    emit AddClaimableToken(ticker, new_token);
  }

  function removeClaimable(bytes32 ticker) public onlyOwner {
    require(combined_offer[ticker] == address(0), "Combined Offer");
    delete available_tokens[ticker];
    delete custom_claimed[ticker];

    bytes32[] memory _tickers_claimable = tickers_claimable;
    for(uint i=0; i<_tickers_claimable.length; i++) {
      if(_tickers_claimable[i] == ticker) {
        tickers_claimable[i] = _tickers_claimable[tickers_claimable.length - 1];
        break;
      }
    }
    tickers_claimable.pop();
    emit RemoveClaimableToken(ticker);
  }

  function addCombinedOffer(address new_token, bytes32 ticker, uint256 _min_received_percents) external onlyOwner {
    require(available_tokens[ticker] == address(0), "Remove single offer");
    require(address(main_vault) != address(0), "Vault not set");
    combined_offer[ticker] = new_token;
    available_tokens[ticker] = address(main_vault);
    min_received[new_token] = _min_received_percents;
    current_offers.push(ticker);
  }

  function removeCombinedOffer(bytes32 ticker) external onlyOwner {
    delete combined_offer[ticker];

    bytes32[] memory _current_offers = current_offers;
    for(uint i=0; i<_current_offers.length; i++) {
      if(_current_offers[i] == ticker) {
        current_offers[i] = _current_offers[current_offers.length - 1];
        break;
      }
    }
    current_offers.pop();
    removeClaimable(ticker);
  }

  /// @dev default = burned
  function setLPRecipient(address _LP_recipient) external onlyOwner {
    LP_recipient = _LP_recipient;
  }

  function setDevWallet(address _devWallet) external onlyOwner {
    devWallet = _devWallet;
  }

  function setMarketingWallet(address _mktWallet) external onlyOwner {
    mktWallet = _mktWallet;
  }

  function setTaxRates(uint8 _dev, uint8 _market, uint8 _balancer, uint8 _reserve) external onlyOwner {
    taxes.dev = _dev;
    taxes.market = _market;
    taxes.balancer = _balancer;
    taxes.reserve = _reserve;
  }

  function setSwapFor_Liq_Threshold(uint128 threshold_in_token) external onlyOwner {
    swap_for_liquidity_threshold = threshold_in_token * 10**_decimals;
  }

  function setSwapFor_Reward_Threshold(uint128 threshold_in_token) external onlyOwner {
    swap_for_reward_threshold = threshold_in_token * 10**_decimals;
  }

  function setSwapFor_Reserve_Threshold(uint128 threshold_in_token) external onlyOwner {
    swap_for_reserve_threshold = threshold_in_token * 10**_decimals;
  }

  function setSellingTaxesTranches(uint16[3] memory new_tranches) external onlyOwner {
    selling_taxes_tranches = new_tranches;
    emit TaxRatesChanged();
  }

  function setSellingTaxesrates(uint8[4] memory new_amounts) external onlyOwner {
    selling_taxes_rates = new_amounts;
    emit TaxRatesChanged();
  }

  function setSmartpoolVar(uint8 _excess_rate, uint8 _minor_fill, uint8 _resplenish_factor, uint32 _freq_check) external onlyOwner {
    excess_rate = _excess_rate;
    minor_fill = _minor_fill;
    resplenish_factor = _resplenish_factor;
    smart_pool_freq = _freq_check;
  }
  
  function setRewardTaxesTranches(uint8 _pcs_pool_to_circ_ratio) external onlyOwner {
    pcs_pool_to_circ_ratio = _pcs_pool_to_circ_ratio;
  }

  function setMaxSlippage(address token, uint256 new_max) external onlyOwner {
    min_received[token] = new_max;
  }

  function setClaimingTaxesRates(uint8[5] memory new_tranches) external onlyOwner {
    claiming_taxes_rates = new_tranches;
  }

  function setClaimingPeriodicity(uint new_period) external onlyOwner {
    claim_periodicity = new_period;
  }

  function addOwner(address _new) external onlyOwner {
    require(!isOwner[_new], "Already owner");
    isOwner[_new] = true;
  }

  function removeOwner(address _adr) external onlyOwner {
    require(isOwner[_adr], "Not an owner");
    isOwner[_adr] = false;
  }

// ---------- frontend ---------------
  function getCurrentOffers() external view returns (bytes32[] memory) {
    return current_offers;
  }

  function getCurrentClaimable() external view returns (bytes32[] memory) {
    return tickers_claimable;
  }

  function endOfWaitingTime() external view returns (uint256) {
    return _last_tx[msg.sender].last_claim + claim_periodicity;
  } 

  /// @notice returns quote as number of token received for amount BNB
  /// @dev returns 0 for non-claimable tokens
  function getQuote(bytes32 ticker) external view returns (uint256 amount, uint8 dec) {
    address wbnb = WETH;
    (amount,,) = computeReward();

    //combined offer ?
    address dest_token = available_tokens[ticker] == address(main_vault) ? combined_offer[ticker] : available_tokens[ticker];
    if(available_tokens[ticker] == address(0)) return (0, 0);
    if(available_tokens[ticker] == wbnb) return (amount, 18);

    address[] memory route = new address[](2);
    route[0] = wbnb;
    route[1] = dest_token;

    try IDec(dest_token).decimals() returns (uint8 _dec) {
        dec = _dec;
      } catch {
        dec=18;
      } //yeah, could've been part of ERC20...

    try router.getAmountsOut(amount, route) returns (uint256[] memory out) {
      return (out[1], dec);
    } catch {
      return (0,0);
    }
  }

}