// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;


interface IAlgebraPool {
    function globalState() external view returns(uint160 price, int24 tick, uint16 fee, 
        uint16 timePointIndex, uint8 communityFeeToken0, uint8 communityFeeToken1, bool unlocked);
    function token0() external view returns(address);
    function token1() external view returns(address);

}