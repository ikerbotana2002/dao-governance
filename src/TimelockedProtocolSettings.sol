// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TimelockedProtocolSettings {
    error InvalidTimelock();
    error OnlyTimelock();
    error FeeTooHigh(uint256 requested);

    address public immutable timelock;

    uint256 public marketplaceFeeBps = 250;

    event MarketplaceFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    constructor(address timelock_) {
        if (timelock_ == address(0)) {
            revert InvalidTimelock();
        }

        timelock = timelock_;
    }

    function setMarketplaceFeeBps(uint256 newFeeBps) external {
        if (msg.sender != timelock) {
            revert OnlyTimelock();
        }

        if (newFeeBps > 1_000) {
            revert FeeTooHigh(newFeeBps);
        }

        uint256 oldFeeBps = marketplaceFeeBps;

        marketplaceFeeBps = newFeeBps;

        emit MarketplaceFeeUpdated(oldFeeBps, newFeeBps);
    }
}
