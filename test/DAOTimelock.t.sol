// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";

import {TimelockedDAOGovernance} from "../src/TimelockedDAOGovernance.sol";

import {TimelockedProtocolSettings} from "../src/TimelockedProtocolSettings.sol";

contract DAOTimelockTest is Test {
    GovernanceToken token;
    TimelockController timelock;
    TimelockedDAOGovernance governor;
    TimelockedProtocolSettings settings;

    address alice = address(0xA1);
    address david = address(0xD1);

    uint256 constant MIN_DELAY = 2 days;

    string constant DESCRIPTION = "Reduce marketplace fee from 2.5% to 1%";

    function setUp() public {
        token = new GovernanceToken();

        token.transfer(alice, 500 ether);

        vm.prank(alice);
        token.delegate(alice);

        // Start with no proposers or executors.
        address[] memory empty = new address[](0);

        // The test contract temporarily administers setup.
        timelock = new TimelockController(MIN_DELAY, empty, empty, address(this));

        governor = new TimelockedDAOGovernance(IVotes(address(token)), timelock);

        // Authorize only the Governor for governance operations.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));

        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Remove the temporary setup administrator.
        // The timelock remains its own administrator.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        settings = new TimelockedProtocolSettings(address(timelock));
    }

    function _action(uint256 newFeeBps)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = address(settings);
        values[0] = 0;

        calldatas[0] = abi.encodeCall(TimelockedProtocolSettings.setMarketplaceFeeBps, (newFeeBps));
    }

    function _descriptionHash() internal pure returns (bytes32) {
        return keccak256(bytes(DESCRIPTION));
    }

    function _passProposal() internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(100);

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, DESCRIPTION);

        // Start the voting period.
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // Alice votes FOR with 500 voting tokens.
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Finish voting.
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function _queueProposal() internal returns (uint256 proposalId) {
        proposalId = _passProposal();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(100);

        vm.prank(david);
        governor.queue(targets, values, calldatas, _descriptionHash());
    }

    function _executeProposal() internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(100);

        // David submits execution through the Governor.
        vm.prank(david);
        governor.execute(targets, values, calldatas, _descriptionHash());
    }

    function testTimelockPermissions() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));

        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)));

        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));

        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));

        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));

        assertEq(settings.timelock(), address(timelock));
    }

    function testAliceCannotChangeFeeDirectly() public {
        vm.expectRevert(TimelockedProtocolSettings.OnlyTimelock.selector);

        vm.prank(alice);
        settings.setMarketplaceFeeBps(100);

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testCannotQueuePendingProposal() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(100);

        vm.prank(alice);
        governor.propose(targets, values, calldatas, DESCRIPTION);

        vm.expectRevert();

        governor.queue(targets, values, calldatas, _descriptionHash());
    }

    function testCannotExecuteWithoutQueuing() public {
        _passProposal();

        vm.expectRevert();
        _executeProposal();

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testQueuingDoesNotExecuteProposal() public {
        uint256 proposalId = _queueProposal();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        assertTrue(governor.proposalNeedsQueuing(proposalId));

        assertGt(governor.proposalEta(proposalId), 0);

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testCannotExecuteBeforeDelay() public {
        uint256 proposalId = _queueProposal();

        uint256 eta = governor.proposalEta(proposalId);

        // One second before the operation is ready.
        vm.warp(eta - 1);

        vm.expectRevert();
        _executeProposal();

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testExecuteAfterDelay() public {
        uint256 proposalId = _queueProposal();

        uint256 eta = governor.proposalEta(proposalId);

        // Simulate the timelock delay expiring.
        vm.warp(eta);

        // Anyone can submit execution through Governor.
        _executeProposal();

        assertEq(settings.marketplaceFeeBps(), 100);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function testCannotExecuteTwice() public {
        uint256 proposalId = _queueProposal();

        vm.warp(governor.proposalEta(proposalId));

        _executeProposal();

        vm.expectRevert();
        _executeProposal();
    }

    function testWrongActionCannotExecute() public {
        uint256 proposalId = _queueProposal();

        vm.warp(governor.proposalEta(proposalId));

        // Proposal approved 100 BPS, not 150 BPS.
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(150);

        vm.expectRevert();

        vm.prank(david);
        governor.execute(targets, values, calldatas, _descriptionHash());

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testAliceCannotScheduleDirectly() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _action(100);

        vm.expectRevert();

        vm.prank(alice);
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(uint256(123)), MIN_DELAY);
    }

    function testFormerAdminCannotGrantRoles() public {
        // Get the roles before expecting a revert.
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        // Verify the test contract is no longer an admin.
        assertFalse(timelock.hasRole(adminRole, address(this)));

        // Only the timelock administrator can grant roles.
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", address(this), adminRole)
        );

        timelock.grantRole(proposerRole, alice);
    }
}
