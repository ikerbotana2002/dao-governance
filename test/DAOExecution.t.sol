// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";

import {DAOGovernance} from "../src/DAOGovernance.sol";

import {ProtocolSettings} from "../src/ProtocolSettings.sol";

contract DAOExecutionTest is Test {
    GovernanceToken token;
    DAOGovernance governor;
    ProtocolSettings settings;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address david = address(0xD1);

    string constant DESCRIPTION = "Reduce marketplace fee from 2.5% to 1%";

    function setUp() public {
        token = new GovernanceToken();

        token.transfer(alice, 500 ether);
        token.transfer(bob, 300 ether);

        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        governor = new DAOGovernance(IVotes(address(token)));

        settings = new ProtocolSettings(address(governor));
    }

    function _feeAction(uint256 newFeeBps) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ProtocolSettings.setMarketplaceFeeBps.selector, newFeeBps);
    }

    function _actionArrays(address target, bytes memory callData)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = target;
        values[0] = 0;
        calldatas[0] = callData;
    }

    function _propose(address target, bytes memory callData, string memory description)
        internal
        returns (uint256 proposalId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _actionArrays(target, callData);

        vm.prank(alice);

        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _execute(address target, bytes memory callData, string memory description) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _actionArrays(target, callData);

        bytes32 descriptionHash = keccak256(bytes(description));

        // David is not the proposer or a voter.
        vm.prank(david);

        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function _passProposal(address target, bytes memory callData, string memory description)
        internal
        returns (uint256 proposalId)
    {
        proposalId = _propose(target, callData, description);

        // Advance beyond the voting snapshot.
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // Alice votes FOR with 500 votes.
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Advance beyond the voting deadline.
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testInitialSettings() public view {
        assertEq(settings.marketplaceFeeBps(), 250);

        assertEq(settings.governor(), address(governor));
    }

    function testDirectUpdatesAreRejected() public {
        vm.expectRevert(ProtocolSettings.Unauthorized.selector);

        vm.prank(alice);
        settings.setMarketplaceFeeBps(100);

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testSucceededProposalDoesNotExecuteAutomatically() public {
        uint256 proposalId = _passProposal(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // Voting passed, but execution has not happened.
        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testApprovedProposalUpdatesFee() public {
        uint256 proposalId = _passProposal(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 250);

        _execute(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 100);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function testCannotExecuteWhileVoting() public {
        uint256 proposalId = _propose(address(settings), _feeAction(100), DESCRIPTION);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Votes are not finalized yet.
        vm.expectRevert();

        _execute(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testDefeatedProposalCannotExecute() public {
        uint256 proposalId = _propose(address(settings), _feeAction(100), DESCRIPTION);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 0);

        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        // 500 AGAINST versus 300 FOR.
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));

        vm.expectRevert();

        _execute(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 250);
    }

    function testCannotExecuteTwice() public {
        _passProposal(address(settings), _feeAction(100), DESCRIPTION);

        _execute(address(settings), _feeAction(100), DESCRIPTION);

        vm.expectRevert();

        _execute(address(settings), _feeAction(100), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 100);
    }

    function testDifferentActionCannotExecute() public {
        uint256 proposalId = _passProposal(address(settings), _feeAction(100), DESCRIPTION);

        // The approved action sets the fee to 100.
        // We attempt to execute an action setting it to 150.
        vm.expectRevert();

        _execute(address(settings), _feeAction(150), DESCRIPTION);

        assertEq(settings.marketplaceFeeBps(), 250);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testInvalidFeeExecutionRevertsAtomically() public {
        uint256 proposalId = _passProposal(address(settings), _feeAction(1_001), "Set fee to an invalid value");

        vm.expectRevert(abi.encodeWithSelector(ProtocolSettings.FeeTooHigh.selector, 1_001));

        _execute(address(settings), _feeAction(1_001), "Set fee to an invalid value");

        // Invalid action didn't modify the settings.
        assertEq(settings.marketplaceFeeBps(), 250);

        // Failed execution didn't mark the proposal executed.
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testGovernanceCanUpdateOwnQuorum() public {
        // Alice cannot update the Governor directly.
        vm.expectRevert();

        vm.prank(alice);
        governor.updateQuorumNumerator(20);

        bytes memory callData = abi.encodeWithSignature("updateQuorumNumerator(uint256)", 20);

        uint256 proposalId = _passProposal(address(governor), callData, "Increase DAO quorum to 20%");

        uint256 snapshot = governor.proposalSnapshot(proposalId);

        assertEq(governor.quorum(snapshot), 100 ether);

        // The Governor executes a call to itself.
        _execute(address(governor), callData, "Increase DAO quorum to 20%");

        assertEq(governor.quorumNumerator(), 20);

        // Historical quorum remains unchanged.
        assertEq(governor.quorum(snapshot), 100 ether);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }
}
