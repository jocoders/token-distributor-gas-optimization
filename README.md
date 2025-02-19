# Gas Optimization Audit Report - TokenVesting

## Overview

- **Contract Audited:** TokenVesting.sol & TokenVestingOptimized.sol
- **Optimization Techniques Used:** Solady library, storage optimization, function unification, constant storage references
- **Audit Focus:** Reducing gas costs for deployment and function execution
- **Findings Summary:**
  - **Deployment Gas Reduced:** 1,251,225 -> 1,248,551 (↓ 0.2%)
  - **Deployment Size Reduced:** 6,797 -> 6,766 (↓ 0.5%)
  - **Gas Savings on Function Calls:** Small improvements across multiple functions

## Optimizations & Gas Savings

### 1️⃣ Replaced OpenZeppelin with Solady for `Ownable` & `SafeTransferLib`

- **Before:** Used OpenZeppelin’s `Ownable` and `SafeTransfer`.
- **After:** Replaced with Solady’s optimized versions.
- **Gas Improvement:** Solady’s functions are more gas-efficient, reducing overhead for ownership and transfers.

### 2️⃣ Packed `beneficiary` and `revocable` into a Single Storage Slot

- **Before:** Stored `beneficiary` (address) and `revocable` (bool) separately.
- **After:** Combined them into a single slot to reduce storage operations.
- **Gas Improvement:** Reduced SLOAD costs by storing them together.

### 3️⃣ Unified `_releasableAmount` and `_vestedAmount` Functions

- **Before:** Had two separate functions performing similar calculations.
- **After:** Merged them into a single function to reduce redundant calls.
- **Gas Improvement:** Saves function execution gas by avoiding duplicated logic.

### 4️⃣ Used Constant Storage References in `_releasableAmount`

- **Before:** Accessed the same storage variables multiple times in `_releasableAmount`.
- **After:** Stored them in memory once and reused them.
- **Gas Improvement:** Reduces redundant SLOAD operations, making calculations cheaper.

## 📊 Gas Usage Comparison (Before vs After)

| Function Name       | Before (Avg) | After (Avg) | Improvement |
| ------------------- | ------------ | ----------- | ----------- |
| **Deployment Cost** | 1,251,225    | 1,248,551   | **↓ 0.2%**  |
| **Deployment Size** | 6,797        | 6,766       | **↓ 0.5%**  |
| `emergencyRevoke`   | 63,780       | 62,563      | **↓ 1.9%**  |
| `getReleased`       | 1,873        | 1,851       | ↓ 1.2%      |
| `getRevoked`        | 2,892        | 2,959       | ↑ 2.3%      |
| `release`           | 93,996       | 92,555      | **↓ 1.5%**  |
| `revoke`            | 75,909       | 74,294      | **↓ 2.1%**  |

## ✅ Conclusion

- **Achieved small gas savings on function executions, particularly `emergencyRevoke` (-1.9%) and `revoke` (-2.1%).**
- **Minor reduction in deployment cost (-0.2%) and contract size (-0.5%).**
- **Most optimizations came from reducing redundant logic and storage operations.**

These changes make `TokenVestingOptimized.sol` slightly more efficient, reducing execution gas and storage costs.
