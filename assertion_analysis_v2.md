# SVA Assertion Failure Analysis v2 — Spec-Only Verdict

> [!IMPORTANT]
> This is a revised analysis based **strictly on the spec** (not assumptions about RTL behavior). My previous analysis incorrectly concluded all failures were assertion bugs. Several are actually **DUT bugs**.

---

## Verdict Summary

| Assertion | Spec Requirement | Verdict | Reasoning |
|---|---|---|---|
| `a_sclk_idle` | R4 | **DUT bug** (mostly) + minor assertion issue | SCLK doesn't match CPOL when idle — spec is absolute |
| `a_xfer_length` | R7 | **Assertion bug** | Counter accumulates across burst words; strobe derivation flawed |
| `a_ss_stable` | R20, §4.2 | **Assertion correct** — test issues | Error injection deliberately violates; clk_div test timeout |
| `a_mosi_stable` | R5 | **Could be either** — needs investigation | DIV=0 is a valid config per R24; spec says MOSI must be stable |

---

## 1. `a_sclk_idle` — **Mostly DUT Bug**

### Spec says (R4, R3, §7.1):
- **R4**: *"For each SPI mode, SCLK idle polarity matches CPOL **before, between, and after** transfers."*
- **R3**: *"CTRL.EN=0 holds the shifter and FIFOs in reset; SCLK stays at CPOL idle."*
- **§7.1**: *"On reset: SCLK is driven to the CPOL=0 idle (low) level until CTRL is programmed."*
- **§10.2 Mandatory Assertion**: *"SCLK idle level matches CPOL whenever BUSY=0."*

The spec is **absolute** — no settling time, no grace period. When BUSY=0, SCLK must equal CPOL. Period.

### Evidence of DUT bug:

**Pattern 1 — Post-transfer SCLK wrong (loopback_test, mode_coverage_test):**
```
# Test 6 — Mode 2 (switching from Mode 1, CPOL=0→1)
# SCLK=1, CPOL=0   Time: 7505 ns   ← CPOL still 0 from Mode 1, SCLK=1 (should be 0!)
# SCLK=1, CPOL=0   Time: 7515 ns
# ...
# SCLK=1, CPOL=1   Time: 7555 ns   ← CPOL just changed to 1, now matches
```
After Mode 1 (CPOL=0) completes, SCLK should idle LOW (CPOL=0). But SCLK is HIGH. The assertion has already waited `idle_cnt > cfg_clk_div + 1` cycles — this isn't a timing race. **The DUT failed to return SCLK to its idle level after the transfer.**

**Pattern 2 — Post-Mode 3 SCLK wrong:**
```
# Test 8 — switching from Mode 3 (CPOL=1) to Mode 0 (CPOL=0)
# SCLK=0, CPOL=1   Time: 9605 ns   ← CPOL still 1 from Mode 3, SCLK=0 (should be 1!)
# ...14 more fires...
# SCLK=0, CPOL=0   Time: 9745 ns   ← CPOL changed to 0, now matches
```
After Mode 3 (CPOL=1), SCLK should idle HIGH. But it's LOW. Same bug.

**Pattern 3 — Post-reset SCLK wrong (fifo_stress_test):**
```
# Time: 305 ns   SCLK=1, CPOL=0   ← Right after reset!
# Time: 315 ns   SCLK=1, CPOL=0
# ...fires for ~400ns...
```
Per §7.1, after reset SCLK must be LOW (CPOL=0 idle). SCLK is HIGH at 305ns — that's 255ns (25+ PCLK cycles) after reset deasserts at 50ns. **The DUT's SCLK is wrong after reset.**

### Minor assertion issue:
The assertion's `idle_cnt` guard adds a grace period that the spec doesn't mention — making it actually **weaker** than the spec. The fires at the very last cycle where `SCLK=1, CPOL=1` (after CPOL just changed) are a one-cycle artifact of the CPOL register write propagating. You could reset `idle_cnt` on CPOL change to avoid these single-cycle edge cases, but the underlying problem is the DUT.

### Conclusion:
**The DUT violates R4.** After transfers in Mode 1/2/3 and after reset, SCLK doesn't return to the correct CPOL idle level. The assertion is largely correct and is catching real bugs.

---

## 2. `a_xfer_length` — **Assertion Bug**

### Spec says (R7, R21):
- **R7**: *"A transfer lasts exactly WIDTH SCLK cycles; BUSY=1 throughout."*
- **R21**: *"DELAY SCLK half-cycles of idle are inserted between consecutive transfers when DELAY > 0 and another word is queued."* — BUSY stays 1 during DELAY.

### Why it's an assertion bug:

The assertion counts `sample_edge` events during BUSY and checks the total when BUSY falls. The problems:

1. **Counter accumulates across burst words**: When DELAY > 0, BUSY stays 1 between words (per R21). The counter never resets between words. Result: `Expected 8, got 13` (= 8 bits from word 1 + 5 phantom edges from delay/word 2).

2. **Strobe derivation counts phantom edges during DELAY**: During inter-transfer delay, the SCLK generator may keep its internal counter running while holding SCLK at idle level. The assertion's `sample_edge = (sclk_cnt == cfg_clk_div) && (sclk_phase == X)` fires on these phantom strobes.

3. **DUT timeout causes undercount**: In clk_div_corner_test, `Expected 8, got 7` happens when the test times out and aborts (`CHECKER_ERROR: wait_idle: DUT hung?`). The transfer wasn't complete — the count is legitimately 7 because the test killed it early.

### Evidence:
- Error injection: `Expected 8, got 13` — multi-word accumulation
- FIFO stress: `Expected 16, got 21` — 16 + 5 phantom edges
- Delay test: `Expected 8, got 9` — off-by-one from delay strobe
- Clk div: `Expected 8, got 7` — aborted transfer

### Conclusion:
R7 says each transfer is exactly WIDTH cycles. The **DUT likely does the right thing** (data is correct in loopback/delay tests). The assertion's counter logic is broken for multi-word and DELAY scenarios.

---

## 3. `a_ss_stable` — **Assertion Correct, Test Issues**

### Spec says (§4.2, R20):
- *"SS_n MUST remain asserted for the full transfer (first launch edge through BUSY deassertion)."*
- *"The IP never toggles SS_n autonomously."*

### Why the assertion is correct:
The assertion `(BUSY && $past(BUSY)) |-> $stable(ss_n)` directly encodes the spec requirement. SS_n must not change during a transfer.

### Why it fires:

**Error injection test**: The test *intentionally* changes SS_CTRL mid-transfer to test error handling. The assertion correctly catches the spec violation. Fix: use `$assertoff` around intentional error injection.

**Clk div corner test**: The test's `wait_idle` timeout is too short for large DIV values (DIV=1024 → 8-bit transfer needs ~16,400 PCLK cycles). The test gives up and deasserts SS_n while BUSY is still 1. Fix: increase test timeout, not the assertion.

### Conclusion:
Assertion is spec-correct. The fires are from test behavior, not DUT bugs.

---

## 4. `a_mosi_stable` — **Needs Investigation (Could Be Either)**

### Spec says (R5, R24):
- **R5**: *"For each SPI mode, MOSI is stable across the sample edge."*
- **R24**: *"CLK_DIV=0 yields SCLK = PCLK/2"* — this is a valid configuration.
- **§10.2**: *"MOSI stable for at least 1 PCLK around each sample edge."*

### The ambiguity:
At DIV=0, SCLK = PCLK/2. Launch and sample edges are on adjacent PCLK cycles. MOSI changes on the launch edge (1 PCLK before sample). The assertion checks `$stable(mosi)` on the sample edge, which compares to the previous PCLK cycle — which was the launch edge where MOSI legitimately changed.

The spec says MOSI must be "stable across the sample edge" and "stable for at least 1 PCLK around each sample edge." At DIV=0:
- MOSI changes on cycle N (launch)
- MOSI is sampled on cycle N+1 (sample)
- MOSI is stable from N+1 onward — but `$stable()` looks back to N where it changed

**If this is a DUT bug**: The DUT should ensure MOSI is stable for 1+ PCLK before the sample edge, even at DIV=0. This would mean the DUT needs to launch MOSI earlier.

**If this is an assertion bug**: The assertion's `!$past(launch_edge)` guard should suppress the check when the prior cycle was a launch — but the strobe derivation at DIV=0 may not work correctly.

### Conclusion:
Without seeing the actual MOSI waveform vs. RTL internals, I can't be 100% certain. But the spec does say DIV=0 is valid (R24) and MOSI must be stable (R5). If the DUT can't maintain MOSI stability at DIV=0, it could be a DUT limitation. If the assertion's strobe logic is just wrong at DIV=0, it's an assertion bug. **Most likely assertion bug** since the data integrity is correct in these tests.

---

## Final Revised Verdict

| # | Assertion | Previous Verdict | **Revised Verdict** |
|---|---|---|---|
| 1 | `a_sclk_idle` | ~~Assertion bug~~ | **DUT bug** — SCLK doesn't match CPOL idle per R4 |
| 2 | `a_xfer_length` | Assertion bug | **Assertion bug** — counter logic flawed (unchanged) |
| 3 | `a_ss_stable` | Test/assertion interaction | **Assertion correct, test issues** (unchanged) |
| 4 | `a_mosi_stable` | ~~Assertion bug~~ | **Ambiguous** — likely assertion bug but could be DUT |

> [!WARNING]
> **Key correction**: The `a_sclk_idle` failures are most likely **real DUT bugs**, not assertion bugs. The spec (R4) is absolute: SCLK must equal CPOL whenever BUSY=0. The assertion already has a generous grace period, and it still fires. The DUT is not returning SCLK to its idle level after transfers in Modes 1/2/3 and after reset.
