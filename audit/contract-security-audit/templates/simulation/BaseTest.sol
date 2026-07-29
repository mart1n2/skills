// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @notice Base test contract for audit PoC simulations.
/// Fork setup, token dealing, and label helpers.
abstract contract BaseTest is Test {
    // TODO: Set the RPC URL and fork block for reproducibility
    uint256 internal fork;
    uint256 internal constant FORK_BLOCK = 0; // TODO: set to a recent block

    function setUp() public virtual {
        // Fork is created by forge CLI: --fork-url <RPC>
        // If FORK_BLOCK > 0, pin the block for determinism
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        require(bytes(rpcUrl).length != 0, "RPC_URL env not set");
        if (FORK_BLOCK > 0) {
            fork = vm.createFork(rpcUrl, FORK_BLOCK);
        } else {
            fork = vm.createFork(rpcUrl);
        }
        vm.selectFork(fork);
        _labelContracts();
    }

    /// @dev Override to label protocol contracts for trace readability
    function _labelContracts() internal virtual {
        // TODO: Add labels
        // vm.label(address(0x1234), "Vault");
    }

    /// @dev Deal ERC20 tokens to an address
    function _dealToken(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }

    /// @dev Get block timestamp shorthand
    function _now() internal view returns (uint256) {
        return block.timestamp;
    }
}
