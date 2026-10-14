// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {DAOGovernance} from "../src/DAOGovernance.sol";

contract DAOGovernanceTest is Test {
    GovernanceToken token;
    DAOGovernance governor;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address charlie = address(0xC1);
    address david = address(0xD1);

    function setUp() public {
        token = new GovernanceToken();

        token.transfer(alice, 500 ether);
        token.transfer(bob, 300 ether);
        token.transfer(charlie, 200 ether);

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        vm.prank(charlie);
        token.delegate(charlie);

        governor = new DAOGovernance(IVotes(address(token)));
    }

    function _propose() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(governor);

        uint256[] memory values = new uint256[](1);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateQuorumNumerator(uint256)", 20);

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, "Increase quorum from 10% to 20%");
    }

    function _startVoting(uint256 proposalId) internal {
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
    }

    function _finishVoting(uint256 proposalId) internal {
        vm.roll(governor.proposalDeadline(proposalId) + 1);
    }

    function testGovernorSettings() public view {
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 20);
        assertEq(governor.proposalThreshold(), 0);
        assertEq(governor.quorumNumerator(), 10);
    }

    function testProposalStartsPending() public {
        uint256 proposalId = _propose();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    function testProposalBecomesActive() public {
        uint256 proposalId = _propose();

        _startVoting(proposalId);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));
    }

    function testCannotVoteBeforeVotingStarts() public {
        uint256 proposalId = _propose();

        vm.expectRevert();
        vm.prank(alice);
        governor.castVote(proposalId, 1);
    }

    function testVoteCounting() public {
        uint256 proposalId = _propose();
        _startVoting(proposalId);

        // Alice votes For.
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Bob votes Against.
        vm.prank(bob);
        governor.castVote(proposalId, 0);

        // Charlie abstains.
        vm.prank(charlie);
        governor.castVote(proposalId, 2);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(forVotes, 500 ether);
        assertEq(againstVotes, 300 ether);
        assertEq(abstainVotes, 200 ether);
    }

    function testCannotVoteTwice() public {
        uint256 proposalId = _propose();
        _startVoting(proposalId);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.expectRevert();
        vm.prank(alice);
        governor.castVote(proposalId, 1);
    }

    function testSnapshotPreventsDoubleCounting() public {
        uint256 proposalId = _propose();
        _startVoting(proposalId);

        // Transfer happens AFTER the voting snapshot.
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        // Alice still has 500 votes for this proposal.
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Bob has only 300 votes for this proposal.
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);

        assertEq(forVotes, 800 ether);
    }

    function testProposalSucceeds() public {
        uint256 proposalId = _propose();
        _startVoting(proposalId);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(bob);
        governor.castVote(proposalId, 0);

        _finishVoting(proposalId);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testProposalDefeatedByVotes() public {
        uint256 proposalId = _propose();
        _startVoting(proposalId);

        vm.prank(alice);
        governor.castVote(proposalId, 0);

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        _finishVoting(proposalId);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function testProposalDefeatedWithoutQuorum() public {
        // David receives just 50 IGOV.
        vm.prank(charlie);
        token.transfer(david, 50 ether);

        vm.prank(david);
        token.delegate(david);

        uint256 proposalId = _propose();
        _startVoting(proposalId);

        vm.prank(david);
        governor.castVote(proposalId, 1);

        _finishVoting(proposalId);

        // 50 votes < 100 required for quorum.
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }
}
