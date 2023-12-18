// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function getOraclePrice() external view returns (uint256);
    function getLpPrice() external view returns (uint256);
    function balanceDeployed() external view returns (uint256);
    function balanceLp() external view returns (uint256);
    function balanceLend() external view returns (uint256);
    function balanceDebt() external view returns (uint256);

}
