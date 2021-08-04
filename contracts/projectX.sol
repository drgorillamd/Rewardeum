// SPDX-License-Identifier: GPL - @DrGorilla_md (Tg/Twtr)
// ----           DO NOT CLONE WITH SOLC < 0.8.0          ----

pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/**
 * 
 */

contract projectX is Ownable, IERC20 {

    struct past_tx {
      uint256 cum_sell;
      uint256 last_sell;
      uint256 reward_buffer;
      uint256 last_claim;
    }

    struct smartpool_struct {
      uint256 reward;
      uint256 reserve;
      uint256 prev_reward;
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

    uint8 private _decimals = 9;
    uint8 public pcs_pool_to_circ_ratio = 10;
    uint8 public excess_rate = 100;
    uint8 public minor_fill = 5;
    uint8 public resplenish_factor = 100;
    uint8 public claim_ratio = 80;

    uint32 public smart_pool_freq = 1 days;

    uint256 private _totalSupply = 10**15 * 10**_decimals;
    uint256 public swap_for_liquidity_threshold = 10**13 * 10**_decimals; //1%
    uint256 public last_smartpool_check;
    uint256 liquidity_pool;

    uint8[4] public selling_taxes_rates = [2, 5, 10, 20];
    uint16[3] public selling_taxes_tranches = [200, 500, 1000]; // % and div by 10000 0.012% -0.025% -(...)

    bool public circuit_breaker;
    bool private liq_swap_reentrancy_guard;

    string private _name = "Rewardeum";
    string private _symbol = "REUM";

    address public LP_recipient;
    address public devWallet;
    address public mktWallet;
    address public WETH;

    IUniswapV2Pair public pair;
    IUniswapV2Router02 public router;

    smartpool_struct public smart_pool_balances;
    taxesRates public taxes = taxesRates({dev: 1, market: 1, balancer: 5, reserve: 8});

    event TaxRatesChanged();
    event SwapForCustom(string status);
    event BalancerPools(uint256 reward_liq_pool, uint256 reward_token_pool);
    event RewardTaxChanged();
    event AddLiq(string status);
    event BalancerReset(uint256 new_reward_token_pool, uint256 new_reward_liq_pool);
    event Smartpool(uint256 reward, uint256 reserve, uint256 prev_reward);
    event SmartpoolOverride(uint256 new_reward, uint256 new_reserve);

    constructor (address _router) {
         //create pair to get the pair address
         router = IUniswapV2Router02(_router);
         WETH = router.WETH();
         IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
         pair = IUniswapV2Pair(factory.createPair(address(this), WETH));

         LP_recipient = address(0x000000000000000000000000000000000000dEaD); //LP token: burn
         devWallet = address(0x000000000000000000000000000000000000dEaD);
         mktWallet = address(0x000000000000000000000000000000000000dEaD);

         excluded[msg.sender] = true;
         excluded[address(this)] = true;
         excluded[devWallet] = true; //exclude burn address from max_tx

         circuit_breaker = true; //ERC20 behavior by default/presale
         
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
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

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
        

        if(excluded[sender] == false && excluded[recipient] == false && circuit_breaker == false) {
        
          (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves(); // returns reserve0, reserve1, timestamp last tx
          if(address(this) != pair.token0()) { // 0 := iBNB
            (_reserve0, _reserve1) = (_reserve1, _reserve0);
          }
          
        // ----  Sell tax & timestamp update ----
          if(recipient == address(pair)) {
            sell_tax = sellingTax(sender, amount, _reserve0); //will update the balancer/timestamps too
          }

        // ----  Smart pool funding & reward cycle (re)init ----
          contribution = amount* taxes.reserve / 100;
          smart_pool_balances.reserve += contribution;
          if(last_smartpool_check < block.timestamp + smart_pool_freq) smartPoolCheck();
          if(_balances[recipient] == 0) _last_tx[recipient].last_claim = block.timestamp;
          
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

        //@dev every extra token are collected into address(this), it's the balancer job to then split them
        //between pool and reward, using the dedicated struct
          _balances[address(this)] += sell_tax + balancer_amount + contribution;
          _balances[devWallet] += dev_tax;
          _balances[mktWallet] += mkt_tax;

        }
        //else, by default:
        //  sell_tax = 0;
        //  dev_tax = 0;
        //  balancer_amount = 0;
        //  contribution to smart pool = 0;


        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount - sell_tax - dev_tax - mkt_tax - balancer_amount - contribution;

        emit Transfer(sender, recipient, amount- sell_tax - dev_tax - mkt_tax - balancer_amount - contribution);
        emit Transfer(sender, address(this), sell_tax);
        emit Transfer(sender, address(this), balancer_amount);
        emit Transfer(sender, devWallet, dev_tax);
        emit Transfer(sender, mktWallet, mkt_tax);
    }

    //@dev take a selling tax if transfer from a non-excluded address or from the pair contract exceed
    //the thresholds defined in selling_taxes_thresholds on 24h floating window
    function sellingTax(address sender, uint256 amount, uint256 pool_balance) internal returns(uint256 sell_tax) {

      if(block.timestamp > _last_tx[sender].last_sell + 1 days) {
        _last_tx[sender].cum_sell = 0; // a.k.a The Virgin

      } else {
        uint16[3] memory _tax_tranches = selling_taxes_tranches;

        uint256 new_cum_sum = amount+ _last_tx[sender].cum_sell;

        if(new_cum_sum > pool_balance * _tax_tranches[2] / 10**4) {
          sell_tax = amount * selling_taxes_rates[3] / 100;
        }
        else if(new_cum_sum > pool_balance * _tax_tranches[1] / 10**4) {
          sell_tax = amount * selling_taxes_rates[2] / 100;
        }
        else if(new_cum_sum > pool_balance * _tax_tranches[0] / 10**4) {
          sell_tax = amount * selling_taxes_rates[1] / 100;
        }
        else { sell_tax = amount * selling_taxes_rates[0] / 100; }
      }

      _last_tx[sender].cum_sell = _last_tx[sender].cum_sell + amount;
      _last_tx[sender].last_sell = block.timestamp;

      smart_pool_balances.reserve += sell_tax; //sell tax is for dynamic reward pool:)

      return sell_tax;
    }

// TODO : gas optim

    //@dev take the 9.9% taxes as input, split it between reward and liq subpools
    //    according to pool condition -> circ-pool/circ supply closer to one implies
    //    priority to the reward pool
    function balancer(uint256 amount, uint256 pool_balance) internal {

        address DEAD = address(0x000000000000000000000000000000000000dEaD);
        uint256 unwght_circ_supply = totalSupply() - _balances[DEAD];

        uint256 circ_supply = (pool_balance < unwght_circ_supply * pcs_pool_to_circ_ratio / 100) ? unwght_circ_supply * pcs_pool_to_circ_ratio / 100 : pool_balance;

        liquidity_pool += ((amount * (circ_supply - pool_balance)) * 10**9 / circ_supply) / 10**9;
        smart_pool_balances.reward += ((amount * pool_balance) * 10**9 / circ_supply) / 10**9;

        if(liquidity_pool >= swap_for_liquidity_threshold && !liq_swap_reentrancy_guard) {
            liq_swap_reentrancy_guard = true;
            uint256 token_out = addLiquidity(liquidity_pool); //returns 0 if fail
            liquidity_pool -= token_out;
            liq_swap_reentrancy_guard = false;
        }

        emit BalancerPools(liquidity_pool, smart_pool_balances.reward);
    }

    //@dev when triggered, will swap and provide liquidity
    //    BNBfromSwap being the difference between and after the swap, slippage
    //    will result in extra-BNB for the reward pool (free money for the guys:)
    function addLiquidity(uint256 token_amount) internal returns (uint256) {
      uint256 smart_pool_balance = address(this).balance;

      address[] memory route = new address[](2);
      route[0] = address(this);
      route[1] = WETH;

      if(allowance(address(this), address(router)) < token_amount) {
        _allowances[address(this)][address(router)] = ~uint256(0);
        emit Approval(address(this), address(router), ~uint256(0));
      }
      
      //odd numbers management -> half is smaller than amount.min(half)
      uint256 half = token_amount / 2;
      
      try router.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, route, address(this), block.timestamp) {

          try router.addLiquidityETH{value: address(this).balance}(address(this), half, 0, 0, LP_recipient, block.timestamp) {
            emit AddLiq("addLiq: ok");
            if(address(this).balance > 0) safeTransferETH(owner(), address(this).balance); //shouldn't happen
            return (token_amount / 2) * 2;
          } catch Error(string memory _err) {
            emit AddLiq(_err);
            return 0;
          }

      } catch Error(string memory _err) {
        emit AddLiq(_err);
        return 0;
      }
    }

    //@dev returns reward in $reum
    function computeReward() public view returns(uint256, uint256 tax_to_pay) {

      past_tx memory sender_last_tx = _last_tx[msg.sender];

      //one claim max every 24h
      if (sender_last_tx.last_claim + 1 days > block.timestamp) return (0, 0);

      uint256 balance_without_buffer = sender_last_tx.reward_buffer >= _balances[msg.sender] ? 0 : _balances[msg.sender] - sender_last_tx.reward_buffer;

      // no more linear increase/ "on-off" only
      uint256 _nom = balance_without_buffer * smart_pool_balances.reward * claim_ratio;
      uint256 _denom = totalSupply() * 100; //100 from claim ratio
      uint256 gross_reward = _nom / _denom;

      tax_to_pay = taxOnClaim(gross_reward);
      return (gross_reward - tax_to_pay, tax_to_pay);
    }

    //@dev Compute the tax on claimed reward - labelled in tokens
    function taxOnClaim(uint256 amount) internal view returns(uint256 tax){
      uint256 amount_BNB = getQuote(amount, WETH);
      if(amount_BNB < 0.01 ether) return 0;
      uint256 tax_graph = 2*amount**2 + 3*amount;
      return amount * tax_graph / 100;
    }

    //@dev tax goes to the smartpool reserve
    function claimReward(address dest_token) external returns (uint256) {
      (uint256 claimable, uint256 tax) = computeReward();
      require(claimable > 0, "Claim: 0");

      smart_pool_balances.reward -= (claimable+tax);
      smart_pool_balances.reserve += tax;

      _last_tx[msg.sender].reward_buffer = 0;
      _last_tx[msg.sender].last_claim = block.timestamp;
                
      if(last_smartpool_check < block.timestamp + smart_pool_freq) smartPoolCheck();

      swapForCustom(claimable, msg.sender, dest_token);

      return claimable;
    }

    function smartPoolCheck() internal {
      smartpool_struct memory _smart_pool_bal = smart_pool_balances;

      if (_smart_pool_bal.reserve > _smart_pool_bal.reward * excess_rate / 100) {
        smart_pool_balances.reward += _smart_pool_bal.reserve * minor_fill / 100;
        smart_pool_balances.reserve -= _smart_pool_bal.reserve * minor_fill / 100;
      }
      if (_smart_pool_bal.reward < _smart_pool_bal.prev_reward) {
        uint256 delta_reward = _smart_pool_bal.prev_reward - _smart_pool_bal.reward;
        if (_smart_pool_bal.reserve >= delta_reward) {
          smart_pool_balances.reward += delta_reward * resplenish_factor / 100;
          smart_pool_balances.reserve -= delta_reward * resplenish_factor / 100;
        }
      }
      
      smart_pool_balances.prev_reward = _smart_pool_bal.reward;
      last_smartpool_check = block.timestamp;

      emit Smartpool(smart_pool_balances.reward, smart_pool_balances.reserve, smart_pool_balances.prev_reward);
    }

    function swapForCustom(uint256 token_amount, address receiver, address dest_token) internal returns (uint256) {
      address wbnb = WETH;
      address[] memory route = dest_token == wbnb ? new address[](2) : new address[](3);

      route[0] = address(this);
      route[1] = wbnb;

      if(dest_token != wbnb) {
        route[2] = dest_token;
      }

      if(allowance(address(this), address(router)) < token_amount) {
        _allowances[address(this)][address(router)] = ~uint256(0);
        emit Approval(address(this), address(router), ~uint256(0));
      }

      try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(token_amount, 0, route, receiver, block.timestamp) {
        emit SwapForCustom("SwapForToken: success");
        return token_amount;
      } catch Error(string memory _err) {
        emit SwapForCustom(_err);
        return 0;
      }
    }

    function getQuote(uint256 amount, address dest_token) public view returns (uint256) {
      address wbnb = WETH;
      address[] memory route = dest_token == wbnb ? new address[](2) : new address[](3);

      route[0] = address(this);
      route[1] = wbnb;

      if(dest_token != wbnb) {
        route[2] = dest_token;
      }

      try router.getAmountsOut(amount, route) returns (uint256[] memory out) {
        return out[out.length - 1];
      } catch {
        return 0;
      }
    }

    //@dev taken from uniswapV2 TransferHelper lib
    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }

    //@dev fallback in order to receive BNB from swapToBNB
    receive () external payable {}

    // --------------- Frontend integration ---------------------

    function lastClaim() external view returns (uint256) {
      return _last_tx[msg.sender].last_claim;
    }

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

    function forceSmartpoolCheck() external onlyOwner {
      smartPoolCheck();
    }

    //@dev set the reward (BNB) pool balance, rest of the contract's balance is the reserve
    //will mostly (hopefully) be used on first cycle
    function smartpoolOverride(uint256 reward) external onlyOwner {
      require(_balances[address(this)] >= reward, "SPOverride: inf to contract balance");
      smart_pool_balances.reserve = _balances[address(this)] - reward;
      smart_pool_balances.reward = reward;
      emit SmartpoolOverride(reward, _balances[address(this)] - reward);
    }

    function resetBalancer() external onlyOwner {
      liquidity_pool = _balances[address(this)] - smart_pool_balances.reward - smart_pool_balances.reserve;
      emit BalancerReset(smart_pool_balances.reward + smart_pool_balances.reserve, liquidity_pool);
    }

    //  --------------  setters ---------------------

    //@dev will bypass all the taxes and act as erc20.
    //     pools & balancer balances will remain untouched
    function setCircuitBreaker(bool status) external onlyOwner {
      circuit_breaker = status;
    }

    //@dev default = burn
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
    
    function setPCSToCircRatio(uint8 _pcs_pool_to_circ_ratio) external onlyOwner {
      pcs_pool_to_circ_ratio = _pcs_pool_to_circ_ratio;
    }

}
