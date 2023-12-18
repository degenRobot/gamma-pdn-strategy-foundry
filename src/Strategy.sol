// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

import {IAToken} from "./interfaces/aave/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import {IPool} from "./interfaces/aave/IPool.sol";
import {IAaveOracle} from "./interfaces/aave/IAaveOracle.sol";
import {IGammaVault} from "./interfaces/gamma/IGammaVault.sol";
import {IClearance} from "./interfaces/gamma/IClearance.sol";

import {IUniProxy} from "./interfaces/gamma/IUniProxy.sol";
import {IMasterchef} from "./interfaces/quickswap/IMasterchef.sol";
import {IAlgebraPool} from "./interfaces/quickswap/IAlgebraPool.sol";
import {IUniswapV2Router01} from "./interfaces/quickswap/IUniswap.sol";
import {IRouter} from "./interfaces/quickswap/IRouter.sol";
import {IPoolAddressesProvider} from "./interfaces/aave/IPoolAddressesProvider.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract Strategy is BaseStrategy {
    using SafeERC20 for ERC20;

    struct Position {
        bool zeroDeposit;
        bool customRatio;
        bool customTwap;
        bool ratioRemoved;
        bool depositOverride; // force custom deposit constraints
        bool twapOverride; // force twap check for hypervisor instance
        uint8 version; 
        uint32 twapInterval; // override global twap
        uint256 priceThreshold; // custom price threshold
        uint256 deposit0Max;
        uint256 deposit1Max;
        uint256 maxTotalSupply;
        uint256 fauxTotal0;
        uint256 fauxTotal1;
    }

    constructor(
        address _asset,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        short = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
        wantDecimals = 6;
        shortDecimals = 18;
        _setInterfaces();
        _approveContracts();

    }

    function _setInterfaces() internal {
        router = IUniswapV2Router01(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
        farmToken = IERC20(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);
        IPoolAddressesProvider provider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        oracle = IAaveOracle(provider.getPriceOracle());
        aToken = IAToken(0x625E7708f30cA75bfd92586e17077590C60eb4cD);
        debtToken = IVariableDebtToken(0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351);  

        v3Router = IRouter(0xf5b509bB0909a69B1c207E495f687a596C168E12);
        gammaVault = IGammaVault(0x3Cc20A6795c4b57d9817399F68E83e71C8626580);
        depositPoint = IUniProxy(0xA42d55074869491D60Ac05490376B74cF19B00e6);
        quickswapPool = IAlgebraPool(0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207);  
        clearance = IClearance(0x676644bB8ae1B48BE85b233b82E84Eb74Fa081a8);

    }

    function _approveContracts() internal {
        asset.approve(address(pool), type(uint256).max);        
        asset.approve(address(gammaVault), type(uint256).max);        
        ERC20(address(short)).approve(address(pool), type(uint256).max);   
        ERC20(address(short)).approve(address(gammaVault), type(uint256).max);   
        farmMasterChef = IMasterchef(0x20ec0d06F447d550fC6edee42121bc8C1817b97D);
        ERC20(address(gammaVault)).approve(address(farmMasterChef), type(uint256).max);     
        ERC20(address(farmToken)).approve(address(router), type(uint256).max);
    }

    uint256 public collatUpper = 6700;
    uint256 public collatTarget = 6000;
    uint256 public collatLower = 5300;
    uint256 public debtUpper = 10190;
    uint256 public debtLower = 9810;

    // protocal limits & upper, target and lower thresholds for ratio of debt to collateral
    uint256 public collatLimit = 7500;
    uint256 public priceSourceDiffKeeper = 100;

    uint256 public slippageAdj = 9900; // 99%
    uint256 public basisPrecision = 10000;
    uint8 public pid=4; 

    bool public doPriceCheck = true;
    bool public isPaused = false;

    address public weth;
    IERC20 public short;
    uint8 public wantDecimals;
    uint8 public shortDecimals;
    //IUniswapV2Pair public wantShortLP; // This is public because it helps with unit testing
    IERC20 public farmToken;
    // Contract Interfaces
    //IUniswapV2Router01 public router;
    //IStrategyInsurance public insurance;
    IUniswapV2Router01 public router;
    IRouter public v3Router;
    IPool public pool;
    IAToken public aToken;
    IVariableDebtToken public debtToken;
    IAaveOracle public oracle;
    IGammaVault public gammaVault;
    IUniProxy public depositPoint;
    IMasterchef public farmMasterChef;
    IAlgebraPool public quickswapPool;
    IClearance public clearance;

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        uint256 oPrice = getOraclePrice();
        uint256 _lendAmt = _amount * basisPrecision / (basisPrecision + collatTarget);
        uint256 _borrowAmt = (_lendAmt * collatTarget / basisPrecision) * 1e18 / oPrice;

        _lendWant(_lendAmt);
        _borrow(_borrowAmt);
        _addToLP(_borrowAmt);

        // Any excess funds after should be returned back to AAVE 
        uint256 _excessWant = asset.balanceOf(address(this));
        if (_excessWant > 0) {
            _lendWant(_excessWant);
        }
        _repayDebt();

    }

    function _lendWant(uint256 amount) internal {
        pool.supply(address(asset), amount, address(this), 0);
    }

    function _borrow(uint256 borrowAmount) internal {
        pool.borrow(address(short), borrowAmount, 2, 0, address(this));
    }

    function _getAmountsIn(uint256 _amountShort) internal view returns (uint256 _amount0, uint256 _amount1) {
        uint256 totalWant; 
        uint256 totalShort;
        if (quickswapPool.token0() == address(asset)) {
            (totalWant, totalShort) = gammaVault.getTotalAmounts();
        } else {
             (totalShort, totalWant) = gammaVault.getTotalAmounts();           
        }
        uint256 balWant = asset.balanceOf(address(this));
        uint256 _amountWant = totalWant * _amountShort / totalShort;
        // if we don't have enough want to add to LP, need to scale back amounts we add
        if (balWant < _amountWant) {
            _amountWant = balWant;
            _amountShort = balWant * totalShort / totalWant;
        } 

        if (quickswapPool.token0() == address(asset)) {
            _amount0 = _amountWant;
            _amount1 = _amountShort;
        } else {
            _amount0 = _amountShort;           
            _amount1 = _amountWant;
        }

    }

function _getMaxValues() public view returns(uint256 deposit0Max, uint256 deposit1Max) {
    address clearanceAddress = 0x676644bB8ae1B48BE85b233b82E84Eb74Fa081a8;
    bytes memory data = abi.encodeWithSelector(IClearance.positions.selector, address(gammaVault));

    (bool success, bytes memory returnData) = clearanceAddress.staticcall(data);
    require(success, "Call to Clearance contract failed");

    // Adjusting for tight packing of the first six boolean values
    uint256 offsetDeposit0Max = 9 * 32; // At slot 9 
    uint256 offsetDeposit1Max = 10 * 32; // At slot 10 

    assembly {
        deposit0Max := mload(add(returnData, add(offsetDeposit0Max, 32))) // add 32 for data offset
        deposit1Max := mload(add(returnData, add(offsetDeposit1Max, 32))) // add 32 for data offset
    }

    return (deposit0Max, deposit1Max);
}



    /*
    function _getMaxValues() public view returns(uint256 deposit0Max, uint256 deposit1Max) {
        (,,,,,,,, deposit0Max, deposit1Max,,,,) = clearance.positions(address(gammaVault));
    }
    */

    function _checkMaxAmts(uint256 _amount0 , uint256 _amount1) internal view returns(uint256 , uint256 ) {
        //(,,,,,,,,, uint256 max0, uint256 max1 , , ,) = IClearance(0x676644bB8ae1B48BE85b233b82E84Eb74Fa081a8).position(address(gammaVault));
        /*
        Position memory pos = IClearance(0x676644bB8ae1B48BE85b233b82E84Eb74Fa081a8).position(address(gammaVault));
        uint256 max0 = pos.deposit0Max;
        uint256 max1 = pos.deposit1Max;
        */
        (uint256 max0, uint256 max1) = _getMaxValues();

        if (_amount0 > max0) {
            _amount1 = max0 * _amount1 / _amount0;
            _amount0 = max0;
        }
        if (_amount1 > max1) {
            _amount0 = max1 * _amount0 / _amount1;
            _amount1 = max1;
        }
        return(_amount0, _amount1);
    }

    function _addToLP(uint256 _amountShort) internal {
        (uint256 _amount0, uint256 _amount1) = _getAmountsIn(_amountShort);
        uint256[4] memory _minAmounts;
        // Check Max deposit amounts 
        (_amount0, _amount1) = _checkMaxAmts(_amount0, _amount1);
        // Deposit into Gamma Vault & Farm 
        depositPoint.deposit(_amount0, _amount1, address(this), address(gammaVault), _minAmounts);
        //farmMasterChef.deposit(pid, gammaVault.balanceOf(address(this)), address(this));
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {

        require(_testPriceSource(priceSourceDiffKeeper));
        uint256 _balanceDeployed = balanceDeployed();
        // stratPercent: Percentage of the deployed capital we want to liquidate.
        uint256 stratPercent = _amount  * basisPrecision / _balanceDeployed;
        (uint256 lpTokens, ) = farmMasterChef.userInfo(pid, address(this));
        uint256 _lpOut = lpTokens * stratPercent / basisPrecision;
        if (_lpOut > 0) {
            _withdrawLp(_lpOut);
        }

        uint256 slippage = 0;
        if (stratPercent > 500) {
            // swap to make up the difference in short 
            uint256 shortInShort = balanceShort();
            uint256 debtInShort = balanceDebtInShort();
            if (debtInShort > shortInShort) {
                uint256 debt =
                    _convertShortToWantLP(debtInShort - shortInShort);
                uint256 swapAmountWant =
                    debt * stratPercent / basisPrecision;
                _redeemWant(swapAmountWant);
                slippage = _swapExactWantShort(swapAmountWant);
            } else {
                (, slippage) = _swapExactShortWant((shortInShort - debtInShort) * stratPercent / basisPrecision);
            }
        }
        
        _repayDebt();
        uint256 _redeemAmount = balanceLend() * stratPercent / basisPrecision;
        _redeemWant(_redeemAmount);
        
    }

    function _testPriceSource(uint256 priceDiff) internal view returns (bool) {
        if (doPriceCheck) {
            uint256 oPrice = getOraclePrice();
            uint256 lpPrice = getLpPrice();
            uint256 priceSourceRatio = oPrice*(basisPrecision)/(lpPrice);
            return (priceSourceRatio > basisPrecision - (priceDiff) &&
                priceSourceRatio < basisPrecision + (priceDiff));
        }
        return true;
    }

    function balanceOfWant() public view returns (uint256) {
        return (asset.balanceOf(address(this)));
    }

    // calculate total value of vault assets
    function balanceDeployed() public view returns (uint256) {
        uint256 oPrice = getOraclePrice();
        return balanceLend() - balanceDebt() + balanceLp() + (balanceShort() * oPrice / 1e18);
        //return balanceLend() + balanceLp() - balanceDebt();
    }

    function balanceLend() public view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function balanceLp() public view returns (uint256) {
        uint256 totalWant; 
        uint256 totalShort;
        if (quickswapPool.token0() == address(asset)) {
            (totalWant, totalShort) = gammaVault.getTotalAmounts();
        } else {
             (totalShort, totalWant) = gammaVault.getTotalAmounts();           
        }

        (uint256 lpTokens, ) = farmMasterChef.userInfo(pid, address(this)); // number of LP Tokens user has in farm 
        uint256 lpValue = (totalWant + (totalShort * getOraclePrice() / 1e18)) * (lpTokens + gammaVault.balanceOf(address(this))) / gammaVault.totalSupply();
        return(lpValue);
    }

    function balanceDebt() public view returns (uint256) {
        return _convertShortToWantOracle(balanceDebtInShort());
    }

    function balanceDebtInShort() public view returns (uint256) {
        // Each debtToken is pegged 1:1 with the short token
        return debtToken.balanceOf(address(this));
    }

    function balanceShort() public view returns (uint256) {
        return (short.balanceOf(address(this)));
    }

    function getOraclePrice() public view returns (uint256) {
        uint256 shortOPrice = oracle.getAssetPrice(address(short));
        uint256 wantOPrice = oracle.getAssetPrice(address(asset));
        return
            shortOPrice*(10**(wantDecimals + (18) - (shortDecimals)))/(
                wantOPrice
            );
    }

    function getLpPrice() public view returns (uint256) {
        (uint160 currentPrice, , , , , , ) = quickswapPool.globalState(); 
        uint256 price;
        if (quickswapPool.token0() == address(asset)) { 
            price = ((2 ** 96) * (2 ** 96)) * 1e18 / (uint256(currentPrice) * uint256(currentPrice));
        } else {
            price = 1e18 * uint256(currentPrice) * uint256(currentPrice) / ((2 ** 96) * (2 ** 96));
        }
        
        // TO DO CONVERT PRICE TO SAME FORMAT AS ORACLE PRICE 
        return price;
    }

    // debt ratio - used to trigger rebalancing of debt
    function calcDebtRatio() public view returns (uint256) {
        uint256 totalShort;
        if (quickswapPool.token0() == address(asset)) {
            (, totalShort) = gammaVault.getTotalAmounts();
        } else {
             (totalShort, ) = gammaVault.getTotalAmounts();           
        }

        (uint256 lpTokens, ) = farmMasterChef.userInfo(pid, address(this)); // number of LP Tokens user has in farm 
        uint256 shortInLp = totalShort * (lpTokens + gammaVault.balanceOf(address(this))) / gammaVault.totalSupply();
        return balanceDebtInShort() * basisPrecision / shortInLp;
    }

    // collateral ratio - used to trigger rebalancing of collateral
    function calcCollateralRatio() public view returns (uint256) {
        return (balanceDebtInShort() * getOraclePrice() / 1e18) * basisPrecision / balanceLend();
    }


    function _claimAndSellRewards() internal {
        // CLAIM & SELL REWARDS 
        farmMasterChef.harvest(pid, address(this));
        if (farmToken.balanceOf(address(this)) > 0) {
            router.swapExactTokensForTokens(farmToken.balanceOf(address(this)), 0, _getTokenOutPath(address(farmToken), address(asset)), address(this), block.timestamp);
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        
        if(!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();
        }
        _totalAssets = balanceDeployed() + asset.balanceOf(address(this));
    }

    function _getTokenOutPath(address tokenIn, address tokenOut)
        internal
        view
        returns (address[] memory _path)
    {
        bool isWeth = tokenIn == address(weth) || tokenOut == address(weth);
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = tokenIn;
        if (isWeth) {
            _path[1] = tokenOut;
        } else {
            _path[1] = address(weth);
            _path[2] = tokenOut;
        }
    }

    function _repayDebt() internal {
        uint256 _bal = short.balanceOf(address(this));
        if (_bal == 0) return;

        uint256 _debt = balanceDebtInShort();
        if (_bal < _debt) {
            pool.repay(address(short), _bal, 2, address(this));
        } else {
            pool.repay(address(short), _debt, 2, address(this));
        }
    }

    function _redeemWant(uint256 _redeemAmount) internal {

        // We run this check in case some dust is left & cannot redeem full amount 
        uint256 _bal = balanceLend();
        uint256 _debt = balanceDebt();

        uint256 _maxRedeem = _bal - (_debt * basisPrecision / collatLimit);

        if (_redeemAmount > _maxRedeem) {
            _redeemAmount = _maxRedeem;
        }

        if (_redeemAmount == 0) return;
        pool.withdraw(address(asset), _redeemAmount, address(this));
    }

    function _withdrawLp(uint256 _amountOut) internal {
        farmMasterChef.withdraw(pid, _amountOut, address(this));
        uint256[4] memory _minAmounts;
        gammaVault.withdraw(_amountOut, address(this), address(this), _minAmounts);
    }


    function _swapExactWantShort(uint256 _amount)
        internal
        returns (uint256 slippageWant)
    {
        uint256 amountOut = _convertWantToShortLP(_amount);
        //v3Router.exactInputSingle();
        /*
        uint256[] memory amounts =
            router.swapExactTokensForTokens(
                _amount,
                amountOut*(slippageAdj)/(basisPrecision),
                getTokenOutPath(address(want), address(short)), // _pathWantToShort(),
                address(this),
                now
            );
        slippageWant = _convertShortToWantLP(
            amountOut - (amounts[amounts.length - 1])
        );
        */
    }

    /**
     * @notice
     *  Swaps _amount of short for want
     *
     * @param _amountShort The amount of short to swap
     *
     * @return _amountWant Returns the want amount minus fees
     * @return _slippageWant Returns the cost of fees + slippage in want
     */
    function _swapExactShortWant(uint256 _amountShort)
        internal
        returns (uint256 _amountWant, uint256 _slippageWant)
    {
        _amountWant = _convertShortToWantLP(_amountShort);
        //v3Router.exactInputSingle();
        /*
        uint256[] memory amounts =
            router.swapExactTokensForTokens(
                _amountShort,
                _amountWant*(slippageAdj)/(basisPrecision),
                getTokenOutPath(address(short), address(want)),
                address(this),
                now
            );
        _slippageWant = _amountWant - (amounts[amounts.length - 1]);
        */
    }

    function _swapWantShortExact(uint256 _amountOut)
        internal
        returns (uint256 _slippageWant)
    {
        uint256 amountInWant = _convertShortToWantLP(_amountOut);
        uint256 amountInMax = (amountInWant*(basisPrecision)/(slippageAdj)) + (10); // add 1 to make up for rounding down
        //v3Router.exactOutputSingle();

        /*
        uint256[] memory amounts =
            router.swapTokensForExactTokens(
                _amountOut,
                amountInMax,
                getTokenOutPath(address(want), address(short)),
                address(this),
                now
            );
        _slippageWant = amounts[0] - (amountInWant);
        */
    }


    function _convertShortToWantLP(uint256 _amountShort)
        internal
        view
        returns (uint256)
    {
        return _amountShort * getLpPrice() / 1e18;

    }

    function _convertShortToWantOracle(uint256 _amountShort)
        internal
        view
        returns (uint256)
    {
        return _amountShort * getOraclePrice() / 1e18;
    }

    function _convertWantToShortLP(uint256 _amountWant)
        internal
        view
        returns (uint256)
    {
        return _amountWant * 1e18 / getLpPrice();
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     *
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement withdraw limit logic and any needed state variables.
        
        EX:    
            return TokenizedStrategy.totalIdle();
    }
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, aToken.balanceOf(address(this)));
            _freeFunds(_amount);
    }

    */
}
