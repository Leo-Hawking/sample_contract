# High-Frequency EVM Layer2 Query Lenses 

## Overview
This repository contains a suite of modular, read-only smart contracts designed for low-latency, off-chain data extraction from EVM decentralized exchanges (focusing on Concentrated Liquidity and Aerodrome).

These contracts are **not meant to be deployed**. They are designed to be executed via `eth_call` using the `state_override` parameter. By injecting the compiled bytecode directly into the local state of an RPC node, we can perform complex, multi-call data aggregations atomically within a single JSON-RPC request.

## Architecture
The contracts are split into three tiers based on operational frequency, computational weight, and execution triggers:

* **`MMLensLs.sol` (Lightweight / Market State)**
  
**Purpose:** Ultra-lightweight market state probe.


* **Execution:** Driven continuously by WSS subscriptions (listening to real-time network events/block headers).
  
**Design:** Strictly reads `slot0` and `liquidity`. It contains no loops, no error handling overhead, and performs no bitmap scanning to ensure the absolute minimum RPC execution time.




* **`MMLensLm.sol` (Medium / Position Monitor)**
  
**Purpose:** User asset snapshot.



**Execution:** Triggered conditionally by specific system events (e.g., price thresholds or heartbeats).


**Design:** Calculates active liquidity, wallet balances, and pending rewards. To avoid on-chain enumeration, the caller must supply known NFT token IDs.




* **`MMLensLb.sol` (Big / Base Initialization)**
  
**Purpose:** Pool metadata, AERO emissions, and token ID discovery.



**Execution:** Triggered conditionally at system cold-start and via periodic background refreshes (e.g., every 5 minutes for emissions).



**Design:** Handles heavy enumeration (which is acceptable here due to infrequent execution). It enumerates both user wallet NFTs and gauge-staked NFTs.


