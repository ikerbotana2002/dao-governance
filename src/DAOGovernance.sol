// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";

import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract DAOGovernance is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes governanceToken)
        Governor("IGOV DAO")
        GovernorVotes(governanceToken)
        GovernorVotesQuorumFraction(10)
    {}

    // Wait 1 block after a proposal is created.
    function votingDelay() public pure override returns (uint256) {
        return 1;
    }

    // Voting remains open for 20 blocks.
    function votingPeriod() public pure override returns (uint256) {
        return 20;
    }

    // Anyone can create a proposal.
    function proposalThreshold() public pure override returns (uint256) {
        return 0;
    }
}
