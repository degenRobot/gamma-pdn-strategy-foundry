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

        // Log oracle price from strategy
        console.log("Oracle price", strategy.getOraclePrice());
        console.log("LP price", strategy.getLpPrice());
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        console.log("Balance Deployed : ", strategy.balanceDeployed());            

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        
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
        assertEq(strategy.totalAssets(), _amount, "!total Assets");
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
            _amount / 200,
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
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.totalDebt(), 0, "!totalDebt");
        assertEq(strategy.totalIdle(), _amount, "!totalIdle");

        // Earn Interest
        skip(1 days);

        uint256 toAirdrop = rewardPrice * (_amount * _profitFactor) / MAX_BPS;
        airdrop(rewardToken, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
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

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.totalDebt(), 0, "!totalDebt");
        assertEq(strategy.totalIdle(), _amount, "!totalIdle");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = rewardPrice * (_amount * _profitFactor) / MAX_BPS;
        airdrop(rewardToken, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
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
}
