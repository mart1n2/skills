// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.sol";

interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Flash loan attack PoC template (Aave V3 style).
/// TODO: Replace target addresses and exploit logic.
contract FlashLoanAttackTest is BaseTest {
    // TODO: Set protocol-specific addresses
    address constant AAVE_POOL = address(0); // TODO: Aave V3 Pool
    address constant BORROW_TOKEN = address(0); // TODO: token to flash borrow
    address constant TARGET = address(0); // TODO: vulnerable contract
    uint256 constant BORROW_AMOUNT = 1_000_000e18; // TODO: adjust amount

    function _labelContracts() internal override {
        vm.label(AAVE_POOL, "AavePool");
        vm.label(BORROW_TOKEN, "BorrowToken");
        vm.label(TARGET, "Target");
    }

    function test_flashLoanAttack() public {
        uint256 balBefore = IERC20(BORROW_TOKEN).balanceOf(address(this));

        IPool(AAVE_POOL).flashLoanSimple(
            address(this),
            BORROW_TOKEN,
            BORROW_AMOUNT,
            "",
            0
        );

        uint256 balAfter = IERC20(BORROW_TOKEN).balanceOf(address(this));
        assertGt(balAfter, balBefore, "Attack should be profitable");
    }

    /// @dev Aave V3 flash loan callback
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "unauthorized");

        // ========== TODO: EXPLOIT LOGIC ==========
        // Use the borrowed funds to manipulate the target
        // Example:
        //   IERC20(asset).approve(TARGET, amount);
        //   ITarget(TARGET).deposit(amount);
        //   ITarget(TARGET).exploit();
        //   ITarget(TARGET).withdraw();
        // ==========================================

        // Repay flash loan + premium
        uint256 repayAmount = amount + premium;
        IERC20(asset).approve(AAVE_POOL, repayAmount);
        return true;
    }
}
