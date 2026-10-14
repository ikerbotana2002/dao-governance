// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";

import {TimelockedDAOGovernance} from "../src/TimelockedDAOGovernance.sol";

import {TimelockedProtocolSettings} from "../src/TimelockedProtocolSettings.sol";

contract DAOSecurityTest is Test {
    GovernanceToken token;
    TimelockController timelock;
    TimelockedDAOGovernance governor;
    TimelockedProtocolSettings settings;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address attacker = address(0xBAD);

    uint256 constant MIN_DELAY = 2 days;

    string constant DESCRIPTION = "Reduce marketplace fees to 1%";

    function setUp() public {
        token = new GovernanceToken();

        token.transfer(alice, 500 ether);
        token.transfer(bob, 300 ether);

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        address[] memory empty = new address[](0);

        timelock = new TimelockController(MIN_DELAY, empty, empty, address(this));

        governor = new TimelockedDAOGovernance(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));

        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        settings = new TimelockedProtocolSettings(address(timelock));
    }

    function _payload(address target, bytes memory data)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = target;
        values[0] = 0;
        calldatas[0] = data;
    }

    function _feeData(uint256 fee) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(TimelockedProtocolSettings.setMarketplaceFeeBps.selector, fee);
    }

    function _hash(string memory description) internal pure returns (bytes32) {
        return keccak256(bytes(description));
    }

    function _propose(address proposer, address target, bytes memory data, string memory description)
        internal
        returns (uint256 proposalId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _payload(target, data);

        vm.prank(proposer);

        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _passProposal(address target, bytes memory data, string memory description)
        internal
        returns (uint256 proposalId)
    {
        proposalId = _propose(alice, target, data, description);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function _queue(address target, bytes memory data, string memory description) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _payload(target, data);

        governor.queue(targets, values, calldatas, _hash(description));
    }

    function _execute(address target, bytes memory data, string memory description) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _payload(target, data);

        governor.execute(targets, values, calldatas, _hash(description));
    }

    // ATTACK 1:
    // A wallet with zero voting power tries to
    // pass its own proposal.
    function testZeroTokenProposerCannotPassAlone() public {
        uint256 proposalId = _propose(attacker, address(settings), _feeData(100), DESCRIPTION);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        vm.prank(attacker);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    // ATTACK 2:
    // Moving tokens after the snapshot must not
    // multiply voting power for that proposal.
    function testTransferAfterSnapshotDoesNotMultiplyVotes() public {
        uint256 proposalId = _propose(alice, address(settings), _feeData(100), DESCRIPTION);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // Alice transfers all her tokens.
        vm.prank(alice);
        token.transfer(attacker, 500 ether);

        // Attacker activates the received votes.
        vm.prank(attacker);
        token.delegate(attacker);

        // Alice still has historical snapshot votes.
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Attacker had zero votes at the snapshot.
        vm.prank(attacker);
        governor.castVote(proposalId, 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);

        assertEq(forVotes, 500 ether);

        // Current balances and votes have changed.
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.getVotes(attacker), 500 ether);
    }

    // ATTACK 3:
    // Change the approved calldata before execution.
    function testCannotExecuteDifferentPayloadEvenAfterDelay() public {
        uint256 proposalId = _passProposal(address(settings), _feeData(100), DESCRIPTION);

        _queue(address(settings), _feeData(100), DESCRIPTION);

        vm.warp(governor.proposalEta(proposalId));

        // Proposal approved 100 BPS, not 150.
        vm.expectRevert();

        _execute(address(settings), _feeData(150), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 250);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));
    }

    // ATTACK 4:
    // Call the TimelockController directly,
    // bypassing the Governor.
    function testAttackerCannotExecuteTimelockDirectly() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _payload(address(settings), _feeData(100));

        vm.prank(attacker);
        vm.expectRevert();

        timelock.executeBatch(targets, values, calldatas, bytes32(0), bytes32(0));

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    // ATTACK 5:
    // Unauthorized cancellation of timelock operations.
    function testAttackerCannotCancelTimelockOperations() public {
        vm.prank(attacker);
        vm.expectRevert();

        timelock.cancel(bytes32(uint256(123)));
    }

    // ATTACK 6:
    // Remove the timelock's 48-hour delay.
    function testAttackerCannotRemoveTimelockDelay() public {
        vm.prank(attacker);
        vm.expectRevert();

        timelock.updateDelay(0);

        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    // ATTACK 7:
    // An approved proposal tries to violate
    // the target contract's own safety rules.
    function testBadProposalCannotBypassTargetValidation() public {
        string memory description = "Set fee above maximum";

        uint256 proposalId = _passProposal(address(settings), _feeData(1_001), description);

        _queue(address(settings), _feeData(1_001), description);

        vm.warp(governor.proposalEta(proposalId));

        vm.expectRevert();

        _execute(address(settings), _feeData(1_001), description);

        assertEq(settings.marketplaceFeeBps(), 250);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));
    }

    // GOVERNANCE RISK:
    // A majority can approve a potentially harmful
    // configuration change. The timelock delays it
    // but doesn't veto the DAO's decision.
    function testMajorityCanLowerQuorumThroughGovernance() public {
        bytes memory data = abi.encodeWithSignature("updateQuorumNumerator(uint256)", 0);

        string memory description = "Lower governance quorum to zero";

        uint256 proposalId = _passProposal(address(governor), data, description);

        assertEq(governor.quorumNumerator(), 10);

        _queue(address(governor), data, description);

        vm.warp(governor.proposalEta(proposalId));

        _execute(address(governor), data, description);

        assertEq(governor.quorumNumerator(), 0);
    }
}
