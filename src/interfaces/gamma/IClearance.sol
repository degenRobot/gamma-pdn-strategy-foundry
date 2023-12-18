// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;



interface IClearance {
    function positions(address _pos) external view returns (bool zeroDeposit, bool customRatio, bool customTwap, bool ratioRemoved, bool depositOverride, bool twapOverride, uint8 version, uint32 twapInterval, uint256 priceThreshold, uint256 deposit0Max, uint256 deposit1Max, uint256 maxTotalSupply, uint256 fauxTotal0, uint256 fauxTotal1);
    //function position(address _pos) external view returns (Position memory);
}