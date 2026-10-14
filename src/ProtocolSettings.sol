// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProtocolSettings {
    error InvalidGovernor();
    error Unauthorized();
    error FeeTooHigh(uint256 requested);

    address public immutable governor;

    // Basis points: 250 = 2.5%, 100 = 1%.
    uint256 public marketplaceFeeBps = 250;

    event MarketplaceFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    constructor(address governor_) {
        if (governor_ == address(0)) {
            revert InvalidGovernor();
        }

        governor = governor_;
    }

    function setMarketplaceFeeBps(uint256 newFeeBps) external {
        if (msg.sender != governor) {
            revert Unauthorized();
        }

        // Maximum permitted fee: 10%.
        if (newFeeBps > 1_000) {
            revert FeeTooHigh(newFeeBps);
        }

        uint256 oldFeeBps = marketplaceFeeBps;

        marketplaceFeeBps = newFeeBps;

        emit MarketplaceFeeUpdated(oldFeeBps, newFeeBps);
    }
}
