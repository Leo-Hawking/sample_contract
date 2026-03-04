// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MMLensLm - User asset snapshot
/// @notice Called conditionally (price threshold / heartbeat / event).
///         Caller supplies known token IDs to avoid on-chain enumeration.

interface ILmPool {
    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, bool);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface ILmERC20 {
    function balanceOf(address) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

interface ILmNPM {
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface ILmVoter {
    function gauges(address pool) external view returns (address);
}

interface ILmGauge {
    function earned(
        address token,
        uint256 tokenId
    ) external view returns (uint256);
}

contract MMLensLm {
    struct PositionDetail {
        uint256 tokenId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool isActive;
    }

    struct UserSnapshot {
        uint256 walletBalance0;
        uint256 walletBalance1;
        uint256 walletUsable0;
        uint256 walletUsable1;
        uint128 totalLiquidity;
        uint128 activeLiquidity;
        PositionDetail[] positions;
        uint256 pendingReward;
    }

    /// @notice Fetch user asset state for a specific pool.
    /// @param tokenIds Known NFT token IDs (wallet + gauge) to avoid enumeration.
    function getUserSnapshot(
        address pool,
        address npm,
        address voter,
        address rewardToken,
        address user,
        uint256[] calldata tokenIds
    ) external view returns (UserSnapshot memory snap) {
        // Pool tokens
        address t0 = ILmPool(pool).token0();
        address t1 = ILmPool(pool).token1();

        // Wallet balances
        snap.walletBalance0 = ILmERC20(t0).balanceOf(user);
        snap.walletBalance1 = ILmERC20(t1).balanceOf(user);

        // Usable = min(balance, allowance to NPM)
        uint256 a0 = ILmERC20(t0).allowance(user, npm);
        uint256 a1 = ILmERC20(t1).allowance(user, npm);
        snap.walletUsable0 = a0 < snap.walletBalance0
            ? a0
            : snap.walletBalance0;
        snap.walletUsable1 = a1 < snap.walletBalance1
            ? a1
            : snap.walletBalance1;

        // Current tick for active-range check
        (, int24 currentTick, , , , ) = ILmPool(pool).slot0();

        // Gauge address (safe call - may not exist)
        address gauge;
        {
            (bool gOk, bytes memory gRet) = voter.staticcall(
                abi.encodeWithSelector(ILmVoter.gauges.selector, pool)
            );
            if (gOk && gRet.length >= 32)
                gauge = abi.decode(gRet, (address));
        }

        // Iterate known token IDs - no enumeration loop
        uint256 len = tokenIds.length;
        snap.positions = new PositionDetail[](len);
        for (uint256 i; i < len; ) {
            (, , , , , int24 tl, int24 tu, uint128 liq, , , , ) = ILmNPM(npm)
                .positions(tokenIds[i]);

            bool active = currentTick >= tl && currentTick < tu;
            snap.positions[i] = PositionDetail(
                tokenIds[i],
                tl,
                tu,
                liq,
                active
            );
            snap.totalLiquidity += liq;
            if (active) snap.activeLiquidity += liq;

            // Pending AERO from gauge (safe)
            if (gauge != address(0)) {
                (bool ok, bytes memory ret) = gauge.staticcall(
                    abi.encodeWithSelector(
                        ILmGauge.earned.selector,
                        rewardToken,
                        tokenIds[i]
                    )
                );
                if (ok && ret.length >= 32) {
                    snap.pendingReward += abi.decode(ret, (uint256));
                }
            }
            unchecked {
                ++i;
            }
        }
    }
}
