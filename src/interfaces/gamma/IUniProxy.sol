// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;


interface IUniProxy {
    function deposit(uint256 _amount0, uint256 _amount1, address _to, address _pos, uint256[4] memory _minAmounts) external;
}