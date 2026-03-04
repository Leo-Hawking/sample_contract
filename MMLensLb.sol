// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MMLensLb - Pool metadata, AERO emissions, and token ID discovery
/// @notice Called at cold start + periodic refresh (e.g. every 5 min for emissions).
///         Heavy enumeration is acceptable here since it runs infrequently.

interface ILbPool {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function tickSpacing() external view returns (int24);
}

interface ILbERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}

interface ILbNPM {
    function balanceOf(address owner) external view returns (uint256);

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256);

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96,
            address,
            address token0,
            address token1,
            int24 tickSpacing,
            int24,
            int24,
            uint128,
            uint256,
            uint256,
            uint128,
            uint128
        );
}

interface ILbVoter {
    function gauges(address pool) external view returns (address);
}

interface ILbGauge {
    // Aerodrome CL gauge uses stakedValues(address) instead of ERC721 enumeration
    function stakedValues(
        address depositor
    ) external view returns (uint256[] memory);

    function rewardRate() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function periodFinish() external view returns (uint256);

    function left(address token) external view returns (uint256);
}

contract MMLensLb {
    struct PoolMeta {
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
        string symbol0;
        string symbol1;
        int24 tickSpacing;
        address gaugeAddress;
    }

    struct EmissionData {
        uint256 rewardRate; // AERO per second
        uint256 totalSupply; // gauge total staked
        uint256 periodFinish; // epoch end timestamp
        uint256 rewardLeft; // remaining rewards in current epoch
    }

    struct TokenIdSet {
        uint256[] walletIds; // NFTs in user wallet (filtered for this pool)
        uint256[] gaugeIds; // NFTs staked in gauge
    }

    // ── Pool Metadata ──

    function getPoolMeta(
        address pool,
        address voter
    ) external view returns (PoolMeta memory m) {
        m.token0 = ILbPool(pool).token0();
        m.token1 = ILbPool(pool).token1();
        m.tickSpacing = ILbPool(pool).tickSpacing();

        // decimals (safe)
        try ILbERC20(m.token0).decimals() returns (uint8 d) {
            m.decimals0 = d;
        } catch {}
        try ILbERC20(m.token1).decimals() returns (uint8 d) {
            m.decimals1 = d;
        } catch {}

        // symbol (may fail for non-standard tokens)
        try ILbERC20(m.token0).symbol() returns (string memory s) {
            m.symbol0 = s;
        } catch {}
        try ILbERC20(m.token1).symbol() returns (string memory s) {
            m.symbol1 = s;
        } catch {}

        // gauge
        (bool gOk, bytes memory gRet) = voter.staticcall(
            abi.encodeWithSelector(ILbVoter.gauges.selector, pool)
        );
        if (gOk && gRet.length >= 32)
            m.gaugeAddress = abi.decode(gRet, (address));
    }

    // ── AERO Emission Data ──

    function getEmissionData(
        address pool,
        address voter,
        address rewardToken
    ) external view returns (EmissionData memory d) {
        (bool gOk, bytes memory gRet) = voter.staticcall(
            abi.encodeWithSelector(ILbVoter.gauges.selector, pool)
        );
        if (!gOk || gRet.length < 32) return d;
        address gauge = abi.decode(gRet, (address));
        if (gauge == address(0)) return d;

        (bool r1, bytes memory v1) = gauge.staticcall(
            abi.encodeWithSelector(ILbGauge.rewardRate.selector)
        );
        if (r1 && v1.length >= 32)
            d.rewardRate = abi.decode(v1, (uint256));

        (bool r2, bytes memory v2) = gauge.staticcall(
            abi.encodeWithSelector(ILbGauge.totalSupply.selector)
        );
        if (r2 && v2.length >= 32)
            d.totalSupply = abi.decode(v2, (uint256));

        (bool r3, bytes memory v3) = gauge.staticcall(
            abi.encodeWithSelector(ILbGauge.periodFinish.selector)
        );
        if (r3 && v3.length >= 32)
            d.periodFinish = abi.decode(v3, (uint256));

        (bool r4, bytes memory v4) = gauge.staticcall(
            abi.encodeWithSelector(ILbGauge.left.selector, rewardToken)
        );
        if (r4 && v4.length >= 32)
            d.rewardLeft = abi.decode(v4, (uint256));
    }

    // ── Token ID Discovery ──

    /// @notice Enumerate user's NFTs (wallet + gauge). Only called at startup.
    /// @dev Uses safe staticcall for NPM (returns 0-byte on zero balance)
    ///      and stakedValues(address) for Aerodrome CL gauge.
    function discoverTokenIds(
        address pool,
        address npm,
        address voter,
        address user,
        uint16 maxWallet,
        uint16 /* maxGauge - unused, gauge returns all at once */
    ) external view returns (TokenIdSet memory set) {
        // Identify pool by token pair + tickSpacing
        address pt0 = ILbPool(pool).token0();
        address pt1 = ILbPool(pool).token1();
        int24 ps = ILbPool(pool).tickSpacing();

        // 1. Enumerate wallet NFTs (safe: NPM may return 0 bytes for 0 balance)
        uint256 bal;
        {
            (bool bOk, bytes memory bRet) = npm.staticcall(
                abi.encodeWithSelector(ILbNPM.balanceOf.selector, user)
            );
            if (bOk && bRet.length >= 32)
                bal = abi.decode(bRet, (uint256));
        }

        if (bal > 0) {
            uint256 scanLen = bal < maxWallet ? bal : maxWallet;
            uint256[] memory tmp = new uint256[](scanLen);
            uint256 count;
            for (uint256 i; i < scanLen; ) {
                // tokenOfOwnerByIndex (safe)
                (bool tOk, bytes memory tRet) = npm.staticcall(
                    abi.encodeWithSelector(
                        ILbNPM.tokenOfOwnerByIndex.selector,
                        user,
                        i
                    )
                );
                if (!tOk || tRet.length < 32) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }
                uint256 tid = abi.decode(tRet, (uint256));

                // positions() - filter by pool match (safe)
                (bool pOk, bytes memory pRet) = npm.staticcall(
                    abi.encodeWithSelector(ILbNPM.positions.selector, tid)
                );
                if (pOk && pRet.length >= 160) {
                    // Decode token0, token1, tickSpacing from positions
                    // positions returns: (uint96, address, address, address, int24, int24, int24, uint128, ...)
                    // Offsets: token0 @ slot 2 (offset 64), token1 @ slot 3 (offset 96), tickSpacing @ slot 4 (offset 128)
                    address t0;
                    address t1;
                    int24 sp;
                    assembly {
                        t0 := mload(add(pRet, 96)) // slot 2
                        t1 := mload(add(pRet, 128)) // slot 3
                        sp := mload(add(pRet, 160)) // slot 4
                    }
                    if (t0 == pt0 && t1 == pt1 && sp == ps) {
                        tmp[count++] = tid;
                    }
                }
                unchecked {
                    ++i;
                }
            }
            set.walletIds = new uint256[](count);
            for (uint256 i; i < count; ) {
                set.walletIds[i] = tmp[i];
                unchecked {
                    ++i;
                }
            }
        }

        // 2. Gauge-staked NFTs via stakedValues(address) — single call
        (bool gOk, bytes memory gRet) = voter.staticcall(
            abi.encodeWithSelector(ILbVoter.gauges.selector, pool)
        );
        if (!gOk || gRet.length < 32) return set;
        address gauge = abi.decode(gRet, (address));
        if (gauge == address(0)) return set;

        (bool svOk, bytes memory svRet) = gauge.staticcall(
            abi.encodeWithSelector(
                ILbGauge.stakedValues.selector,
                user
            )
        );
        if (svOk && svRet.length >= 64) {
            set.gaugeIds = abi.decode(svRet, (uint256[]));
        }
    }
}
