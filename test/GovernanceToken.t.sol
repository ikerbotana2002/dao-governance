// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken public token;

    address public alice = address(0xA1);
    address public bob = address(0xB1);
    address public charlie = address(0xC1);

    function setUp() public {
        token = new GovernanceToken();

        token.transfer(alice, 500 ether);
        token.transfer(bob, 300 ether);
        token.transfer(charlie, 200 ether);
    }

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1_000 ether);
        assertEq(token.balanceOf(alice), 500 ether);
        assertEq(token.balanceOf(bob), 300 ether);
        assertEq(token.balanceOf(charlie), 200 ether);
    }

    function testNoVotesBeforeDelegation() public view {
        assertEq(token.balanceOf(alice), 500 ether);
        assertEq(token.getVotes(alice), 0);
    }

    function testSelfDelegation() public {
        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), 500 ether);
        assertEq(token.delegates(alice), alice);
    }

    function testDelegateVotesToAnotherPerson() public {
        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 500 ether);

        // Alice still owns her 500 tokens.
        assertEq(token.balanceOf(alice), 500 ether);
    }

    function testTransferUpdatesDelegatedVotes() public {
        vm.prank(alice);
        token.delegate(alice);

        vm.prank(bob);
        token.delegate(bob);

        vm.prank(alice);
        token.transfer(bob, 100 ether);

        assertEq(token.getVotes(alice), 400 ether);
        assertEq(token.getVotes(bob), 400 ether);
    }

    function testHistoricalVotesStayUnchanged() public {
        vm.prank(alice);
        token.delegate(alice);

        uint256 snapshotBlock = block.number;

        // Move to the next block.
        vm.roll(block.number + 1);

        vm.prank(alice);
        token.transfer(bob, 100 ether);

        assertEq(token.getPastVotes(alice, snapshotBlock), 500 ether);

        assertEq(token.getVotes(alice), 400 ether);
    }

    function testHistoricalTotalSupply() public {
        uint256 snapshotBlock = block.number;

        vm.roll(block.number + 1);

        assertEq(token.getPastTotalSupply(snapshotBlock), 1_000 ether);
    }

    function testDelegatedVotesFollowTransfers() public {
        vm.prank(alice);
        token.delegate(bob);

        vm.prank(bob);
        token.delegate(bob);

        assertEq(token.getVotes(bob), 800 ether);

        vm.prank(charlie);
        token.delegate(charlie);

        vm.prank(alice);
        token.transfer(charlie, 100 ether);

        assertEq(token.getVotes(bob), 700 ether);
        assertEq(token.getVotes(charlie), 300 ether);
    }
}
