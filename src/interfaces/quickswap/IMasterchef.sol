// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;


interface IMasterchef {
    function deposit(uint256 pid,uint256 amount,address to) external;
    function withdraw(uint256 pid,uint256 amount,address to) external;
    function harvest(uint256 pid,address to) external;
    function userInfo(uint256 pid,address user) external view returns(uint256 _amount, uint256 _rewardDebt);
}