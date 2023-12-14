pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Interface is IERC20 {
    //TODO: Add your specific implementation interface in here.
    function decimals() external view returns(uint256);
}
