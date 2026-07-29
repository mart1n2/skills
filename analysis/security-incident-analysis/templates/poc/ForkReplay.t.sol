// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Incident fork-replay + counterfactual harness.
// Run: forge test --fork-url "$RPC_URL" --fork-block-number $PRE --match-path ForkReplay.t.sol -vvvv
//
// Two tests, both required for a CONFIRMED-DEPLOYED verdict:
//   test_Reproduce      — replay the attack against real deployed state; assert extraction ≈ on-chain figure.
//   test_Counterfactual — neutralize ONLY the hypothesized root cause; assert the drain now fails.
// If test_Counterfactual does NOT stop the drain, the root cause is wrong — go back to methodology §4.

import {Test, console2} from "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

contract ForkReplay is Test {
    // ---- fill from run.env / actors.md ----
    address constant VICTIM = 0x0000000000000000000000000000000000000000; // where assets sat
    address constant ASSET = 0x0000000000000000000000000000000000000000; // drained token (address(0) => native)
    uint256 constant PRE_BLOCK = 0; // parent block of first exploit tx
    uint256 constant ONCHAIN_EXTRACTED = 0; // Phase-5 net figure (base units)

    address attacker;

    function setUp() public {
        // Pin state. Prefer an env fork block so the report is reproducible.
        if (PRE_BLOCK != 0) vm.rollFork(PRE_BLOCK);
        attacker = makeAddr("attacker"); // FRESH address, no pre-funding
        vm.label(VICTIM, "VICTIM");
        if (ASSET != address(0)) vm.label(ASSET, "ASSET");
    }

    function _bal(address who) internal view returns (uint256) {
        return ASSET == address(0) ? who.balance : IERC20(ASSET).balanceOf(who);
    }

    // 1) REPRODUCE — the attack drains the real deployment; profit ≈ on-chain figure.
    function test_Reproduce() public {
        uint256 vBefore = _bal(VICTIM);
        uint256 aBefore = _bal(attacker);

        vm.startPrank(attacker);
        _runExploit(); // <-- implement the exact attack chain (flash loan, setup, drain)
        vm.stopPrank();

        uint256 aGain = _bal(attacker) - aBefore;
        console2.log("victim before:", vBefore);
        console2.log("victim after :", _bal(VICTIM));
        console2.log("attacker gain:", aGain);

        assertLt(_bal(VICTIM), vBefore, "victim did not lose funds");
        assertGt(aGain, 0, "attacker did not profit");
        if (ONCHAIN_EXTRACTED != 0) {
            // within 1% of the observed on-chain extraction => same mechanism, not a lookalike
            assertApproxEqRel(aGain, ONCHAIN_EXTRACTED, 0.01e18, "extraction != on-chain figure");
        }
    }

    // 2) COUNTERFACTUAL — patch ONLY the root cause; the drain must now fail.
    function test_Counterfactual() public {
        _applyFix(); // <-- e.g. vm.mockCall the price to an oracle value / add the missing gate

        uint256 aBefore = _bal(attacker);
        vm.startPrank(attacker);
        bool ok = _tryExploit(); // returns false on revert; assert no meaningful profit if it doesn't revert
        vm.stopPrank();

        uint256 aGain = _bal(attacker) - aBefore;
        assertTrue(!ok || aGain == 0, "fix did NOT stop the drain -> root cause hypothesis is wrong");
    }

    // ---- implement these for the specific incident ----
    function _runExploit() internal {
        revert("implement _runExploit");
    }
    function _applyFix() internal { /* patch the one hypothesized flaw here */ }

    function _tryExploit() internal returns (bool) {
        try this._runExploitExternal() {
            return true;
        } catch {
            return false;
        }
    }

    function _runExploitExternal() external {
        _runExploit();
    }
}
