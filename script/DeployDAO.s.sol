// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";

import {TimelockedDAOGovernance} from "../src/TimelockedDAOGovernance.sol";

import {TimelockedProtocolSettings} from "../src/TimelockedProtocolSettings.sol";

contract DeployDAO is Script {
    uint256 public constant MIN_DELAY = 2 days;

    function run() external {
        address deployer = vm.envAddress("DAO_DEPLOYER");
        address memberB = vm.envAddress("DAO_MEMBER_B");
        address memberC = vm.envAddress("DAO_MEMBER_C");

        require(deployer != address(0) && memberB != address(0) && memberC != address(0), "Invalid member address");

        require(deployer != memberB && deployer != memberC && memberB != memberC, "Duplicate DAO member");

        address[] memory empty = new address[](0);

        vm.startBroadcast(deployer);

        // 1. Deploy the governance token.
        GovernanceToken token = new GovernanceToken();

        // Distribute 1,000 IGOV among three members.
        token.transfer(memberB, 300 ether);
        token.transfer(memberC, 200 ether);

        // Activate the deployer's remaining 500 votes.
        token.delegate(deployer);

        // 2. Deploy a self-administered timelock.
        // The deployer is temporarily an administrator.
        TimelockController timelock = new TimelockController(MIN_DELAY, empty, empty, deployer);

        // 3. Deploy the Governor.
        TimelockedDAOGovernance governor = new TimelockedDAOGovernance(IVotes(address(token)), timelock);

        // 4. Configure timelock roles.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));

        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 5. Deploy settings controlled by the timelock.
        TimelockedProtocolSettings settings = new TimelockedProtocolSettings(address(timelock));

        // 6. Verify critical configuration.
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "Missing proposer role");

        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)), "Missing executor role");

        require(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)), "Missing canceller role");

        require(settings.timelock() == address(timelock), "Incorrect settings controller");

        // 7. Remove the deployer's privileged access.
        // Only the timelock remains its own administrator.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        require(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer), "Deployer is still admin");

        vm.stopBroadcast();

        // Print public deployment information.
        console2.log("GovernanceToken:", address(token));
        console2.log("TimelockController:", address(timelock));
        console2.log("Governor:", address(governor));
        console2.log("ProtocolSettings:", address(settings));
        console2.log("Deployer:", deployer);
        console2.log("Timelock delay:", MIN_DELAY);
    }
}
