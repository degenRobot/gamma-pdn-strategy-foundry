// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use
pragma solidity ^0.8.00;

// https://polygonscan.com/address/0xf5b509bb0909a69b1c207e495f687a596c168e12#code

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 limitSqrtPrice;
}

struct ExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
    uint160 limitSqrtPrice;
}

interface IRouter {
    function exactInputSingle(ExactInputSingleParams memory) external;
    function exactOutputSingle(ExactOutputSingleParams memory) external;
}
