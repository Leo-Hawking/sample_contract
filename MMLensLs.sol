// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MMLensLs - Ultra-lightweight market state probe
/// @notice Called every new block (~2s). Only reads slot0 + liquidity.
///         No loops, no error handling overhead, no bitmap scanning.

interface ILsPool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );

    function liquidity() external view returns (uint128);
}

contract MMLensLs {
    struct MarketState {
        uint160 sqrtPriceX96;
        int24 currentTick;
        uint128 liquidity;
    }

    /// @notice Single-pool market state (2 external calls)
    function getMarketState(address pool)
        external
        view
        returns (MarketState memory s)
    {
        (s.sqrtPriceX96, s.currentTick, , , , ) = ILsPool(pool).slot0();
        s.liquidity = ILsPool(pool).liquidity();
    }

    /// @notice Batch market state for multiple pools
    function getMarketStates(address[] calldata pools)
        external
        view
        returns (MarketState[] memory states)
    {
        uint256 n = pools.length;
        states = new MarketState[](n);
        for (uint256 i; i < n; ) {
            (states[i].sqrtPriceX96, states[i].currentTick, , , , ) = ILsPool(
                pools[i]
            ).slot0();
            states[i].liquidity = ILsPool(pools[i]).liquidity();
            unchecked {
                ++i;
            }
        }
    }
}
