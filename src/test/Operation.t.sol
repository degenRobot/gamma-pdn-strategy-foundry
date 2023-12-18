// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";


contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_deposit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        //(uint256 max0, uint256 max1) = strategy._getMaxValues();
        //console.log("max0 : ", max0);
        //console.log("max1 : ", max1);
        // Log oracle price from strategy
        //console.log("Oracle price", strategy.getOraclePrice());
        //console.log("LP price", strategy.getLpPrice());
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        console.log("Balance Deployed : ", strategy.balanceDeployed());            

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        console.log("Amount : ", _amount);
        console.log("Balance Deployed : ", strategy.balanceDeployed());            
        console.log("Balance LP : ", strategy.balanceLp());
        console.log("Balance Lend : ", strategy.balanceLend());
        console.log("Balance Debt : ", strategy.balanceDebt());
        console.log("Total Assets : ", strategy.totalAssets());

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!total Assets");
        //assertEq(strategy.totalDebt(), 0, "!totalDebt");
        //assertEq(strategy.totalIdle(), _amount, "!totalIdle");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        console.log("Profit : " , profit);
        console.log("Loss : " , loss);

        // Check return Values (due to difference in lending / borrow rates can be some small deviation in profit / loss)
        assertApproxEq(profit, 0, _amount/1000, "!profit");
        assertApproxEq(loss, 0, _amount/1000 ,"!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);
        console.log("Balance Before " , balanceBefore);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        console.log("Balance After : ", asset.balanceOf(user));

        assertApproxEq(
            asset.balanceOf(user),
            balanceBefore + _amount,
            _amount / 500,
            "!total balance"
        );

    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        assertApproxEq(strategy.totalDebt(), _amount, _amount/1000, "!totalDebt");
        assertApproxEq(strategy.totalIdle(), 0, _amount/1000, "!totalIdle");

        // Earn Interest
        skip(1 days);

        uint256 toAirdrop = _amount / 500;
        uint256 airdropAmount = rewardPrice * toAirdrop / MAX_BPS;
        airdrop(rewardToken, address(strategy), airdropAmount);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        console.log("To Airdrop : ", _amount);
        console.log("Profit : ", profit);
        // As price of reward token is volatile have big detla here 
        assertGe(profit, toAirdrop /2, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        assertApproxEq(strategy.totalDebt(), _amount, _amount/1000, "!totalDebt");
        assertApproxEq(strategy.totalIdle(), 0, _amount/1000, "!totalIdle");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = _amount / 500;
        uint256 airdropAmount = rewardPrice * toAirdrop / MAX_BPS;
        airdrop(rewardToken, address(strategy), airdropAmount);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // As price of reward token is volatile have big detla here 
        assertGe(profit, toAirdrop /2, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    function test_withdraw_offset_asset(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        offsetPriceAsset();

        vm.prank(management);
        strategy.setPriceCheck(false);   
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        vm.prank(management);
        strategy.setPriceCheck(true);  
    }

    function test_withdraw_price_offset_check_asset(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        offsetPriceAsset();
        vm.prank(user);
        vm.expectRevert("Price Offset Check");
        strategy.redeem(_amount, user, user);


    }

    function test_withdraw_offset_short(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        offsetPriceShort();
        vm.prank(management);
        strategy.setPriceCheck(false);   
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        vm.prank(management);
        strategy.setPriceCheck(true);  

    }

    function test_withdraw_price_offset_check_short(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertApproxEq(strategy.totalAssets(), _amount, _amount/1000, "!totalAssets");
        offsetPriceShort();

        vm.prank(user);
        vm.expectRevert("Price Offset Check");
        strategy.redeem(_amount, user, user);


    }

}
