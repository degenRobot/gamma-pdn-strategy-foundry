// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;


interface IGammaVault {
    function balanceOf(address _user) external view returns (uint256);
    function addLiquidity(int24 _tickLower, int24 _tickUpper, uint256 _amount0, uint256 _amount1, uint256[2] memory _inMin) external;
    function withdraw(uint256 _shares, address _to, address _from, uint256[4] memory _minAmounts) external;
    function getTotalAmounts() external view returns(uint256 _total0, uint256 _total1);
    function totalSupply() external view returns(uint256);
    function deposit0Max() external view returns(uint256);
    function deposit1Max() external view returns(uint256);
}