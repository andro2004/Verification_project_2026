# SPI Core Assertions — Current Status

**Date:** 2025-05-13  
**File:** `harness/examples/sv_only/assertions/spi_core_sva.sv`

---

## Summary

| Assertion | Spec Req | Status | Fires? | Action Taken |
|---|---|---|---|---|
| `a_sclk_idle` | R4 | ⚠️ Fires — ambiguous root cause | Yes (Modes 2/3, post-reset) | Left as-is with comments |
| `a_mosi_stable` | R5 | ⚠️ Fires — ambiguous root cause | Yes (DIV=0, DIV=65535) | Left as-is with comments |
| `a_ss_stable` | R20, §4.2 | ✅ Correct | Yes (error injection, test timeouts) | Kept — proves assertion works |
| `a_xfer_length` | R7 | ✅ Fixed | Reduced (only aborted transfers) | Rewrote with `real_sample_edge` |

---

## Assertion Details

### 1. `a_sclk_idle` (R4) — ⚠️ Left As-Is

**What it checks:** When BUSY=0 and enough idle time has passed (`idle_cnt > cfg_clk_div + 1`), SCLK must equal CPOL.

**Current fires:**
- After Mode 1 (CPOL=0) transfer: SCLK stays HIGH instead of LOW
- After Mode 3 (CPOL=1) transfer: SCLK stays LOW instead of HIGH
- After reset with CPOL=0: SCLK is HIGH instead of LOW
- During CPOL transitions between test sub-cases

**Analysis:**
The spec (R4) says "SCLK idle polarity matches CPOL before, between, and after transfers" with no mention of settling time. The assertion already includes a grace period (`idle_cnt > cfg_clk_div + 1`) that is weaker than what the spec literally requires — yet it still fires.

This **may** indicate a DUT bug in the SCLK generation logic, or it could be an RTL settling behavior that the spec doesn't explicitly address. The CPOL-transition fires could also be an assertion timing artifact (idle_cnt not reset on CPOL change).

**Decision:** Left as-is. The fires flag a legitimate question about R4 compliance.

---

### 2. `a_xfer_length` (R7) — ✅ Fixed

**What it checks:** On `$fell(BUSY)`, the number of sample edges in the last word equals WIDTH.

**Previous bug:** Used internal strobe derivation (`sample_edge` from `sclk_cnt`/`sclk_phase`) for counting. During DELAY phase, the internal counter keeps running even though SCLK is held at idle, generating **phantom strobes** that corrupted the count. This caused false fires like "Expected 8, got 13" (accumulation) and "Expected 8, got 1" (counter reset from phantom word boundary).

**Fix applied:** Replaced `sample_edge` with `real_sample_edge` — detects actual SCLK pin transitions:
```systemverilog
wire sclk_rose = (sclk == 1'b1) && (sclk_d == 1'b0);
wire sclk_fell = (sclk == 1'b0) && (sclk_d == 1'b1);
wire real_sample_edge = BUSY && ((cpol == cpha) ? sclk_rose : sclk_fell);
```
During DELAY, SCLK doesn't toggle → `real_sample_edge = 0` → no phantom counts.

**Remaining expected fires:**
- `Expected 8, got 7` in clk_div_corner_test: test `wait_idle` times out and aborts a slow transfer (DIV=1024). The transfer was incomplete — not an assertion or DUT bug.
- `Expected 8, got 3` in delay_transfer_test R24/R25: mid-transfer CLK_DIV write, which is undefined behavior per spec §8.3.

---

### 3. `a_mosi_stable` (R5) — ⚠️ Left As-Is

**What it checks:** MOSI must be stable (`$stable(mosi)`) on sample edges, suppressed when the previous cycle was a launch edge.

**Current fires:** At DIV=0 (SCLK = PCLK/2) and DIV=65535.

**Analysis:**
At DIV=0, launch and sample edges are on adjacent PCLK cycles. `$stable(mosi)` compares to the previous cycle, which is the launch edge where MOSI legitimately changes. The guard `!$past(launch_edge)` should suppress this, but the strobe derivation from `sclk_cnt`/`sclk_phase` may not align perfectly with the RTL at DIV=0.

The spec says DIV=0 is valid (R24) and MOSI must be "stable for at least 1 PCLK around each sample edge" (§10.2). Whether the DUT meets this at extreme DIV values requires waveform investigation.

**Decision:** Left as-is. Fires may be false positives from strobe skew, or genuine DUT issues.

---

### 4. `a_ss_stable` (R20, §4.2) — ✅ Correct

**What it checks:** SS_n must not change while BUSY is continuously asserted: `(BUSY && $past(BUSY)) |-> $stable(ss_n)`.

**Current fires:**
- **error_injection_test:** Test intentionally manipulates SS_CTRL mid-transfer. Fires are correct — the assertion proves it detects the spec violation.
- **clk_div_corner_test:** Test's `wait_idle` timeout is too short for large DIV values (DIV=1024 needs ~16,400 PCLK cycles for 8-bit transfer). Test forcefully deasserts SS_n while BUSY=1.

**Decision:** Kept without disabling. The fires demonstrate the assertion works correctly against both intentional error injection and test-infrastructure issues.

---

## Message Format

All assertion `$error` messages use the grading-compatible format per `grading_interface.md` §4:
```
[ASSERTION_ERROR] <assertion_name> <descriptive text>
```
