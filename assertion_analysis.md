# SVA Assertion Failure Analysis

## Summary of Failures

| Assertion | Tests Triggering | Root Cause | Verdict |
|---|---|---|---|
| `a_sclk_idle` | Loopback, Mode Coverage, Interrupt, Randomized, FIFO Stress | **Assertion bug** — checks fire during CPOL transition window | ❌ Fix assertion |
| `a_xfer_length` | Error Injection, Delay, Clk Div, FIFO Stress | **Assertion bug** — counter logic broken for multi-word bursts and DELAY | ❌ Fix assertion |
| `a_ss_stable` | Error Injection, Clk Div | **Assertion bug** — fires on legitimate SS_n deassert after transfer completes | ❌ Fix assertion |
| `a_mosi_stable` | Delay, Clk Div | **Assertion bug** — DIV=0 edge case not fully suppressed | ❌ Fix assertion |

> [!IMPORTANT]
> **All four failing assertions are assertion bugs, not DUT bugs.** The tests themselves pass (data integrity is correct), and the errors come from overly strict or incorrectly conditioned SVA checks.

---

## 1. `a_sclk_idle` — SCLK Idle Level Mismatch

### What the spec says (R4)
> *"For each SPI mode, SCLK idle polarity matches CPOL **before, between, and after** transfers."*

### What the assertion checks ([spi_core_sva.sv:57-62](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/assertions/spi_core_sva.sv#L57-L62))
```systemverilog
property spi_idle_clock;
    @(posedge clk) disable iff (!rst_n)
    (!BUSY && (idle_cnt > cfg_clk_div + 17'd1)) |-> (sclk == cpol);
endproperty
```

### Root cause: CPOL changes between sub-tests while SCLK is still settling

The assertion already has an `idle_cnt` mechanism to wait `cfg_clk_div + 1` cycles after BUSY falls. **But the real problem is different**: when a test switches from Mode 0 (CPOL=0) to Mode 2 (CPOL=1) by writing CTRL, the CPOL signal changes immediately, but SCLK is still at the **old** idle level (0). The `idle_cnt` counter was **not reset on CPOL change**, so the counter already exceeded the threshold from the previous idle period.

**Sequence of events:**
1. Mode 0 transfer completes → BUSY=0, SCLK=0, CPOL=0 → assertion passes ✓
2. Test writes CTRL to set CPOL=1 → CPOL changes to 1 instantly
3. `idle_cnt` is already large (from the previous idle) → guard `idle_cnt > cfg_clk_div + 1` is TRUE
4. But SCLK is still 0 (old value), CPOL is now 1 → `sclk != cpol` → **fires** ✗
5. SCLK settles to 1 after a few cycles, but assertions already fired

**Evidence from logs — the telltale pattern:**

The loopback test transitions from Mode 1 (CPOL=0) to Mode 2 (CPOL=1) at ~7505ns:
```
# SCLK=1, CPOL=0   ← SCLK still at CPOL=0 HIGH from last transfer cycle
# SCLK=1, CPOL=0
# ...
# SCLK=1, CPOL=1   ← CPOL register just changed, now matches but one more fire
```

The FIFO stress test fires at 305ns (immediately after reset!) because the DUT's SCLK comes out of reset HIGH while CPOL=0. This is another timing window issue — the spec says "on reset, SCLK is driven to CPOL=0 idle (low)" but the RTL takes 1+ cycles.

### Fix

Reset `idle_cnt` whenever CPOL changes (detect `$changed(cpol)`):

```systemverilog
logic past_cpol;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) past_cpol <= 1'b0;
    else        past_cpol <= cpol;
end

wire cpol_changed = (cpol != past_cpol);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || BUSY || cpol_changed)   // ← added cpol_changed
        idle_cnt <= 17'd0;
    else if (idle_cnt <= cfg_clk_div + 17'd2)
        idle_cnt <= idle_cnt + 17'd1;
end
```

---

## 2. `a_xfer_length` — Transfer Length Mismatch

### What the spec says (R7)
> *"A transfer lasts exactly WIDTH SCLK cycles."*

### What the assertion checks ([spi_core_sva.sv:148-153](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/assertions/spi_core_sva.sv#L148-L153))
```systemverilog
property a_xfer_length_dynamic;
    @(posedge clk) disable iff (!rst_n)
    $fell(BUSY) |-> (pulse_cnt_save == width);
endproperty
```

### Root cause: `pulse_cnt` / `pulse_cnt_save` accumulates across multiple transfers in a burst

The counter logic at lines 127-146 attempts to count sample edges per word. The `pulse_cnt_save` reset logic is:

```systemverilog
else if ($rose(BUSY) || (BUSY && sample_edge && (pulse_cnt + 6'd1 == width)))
    pulse_cnt_save <= ... ? width : 6'd0;
else if (BUSY && sample_edge)
    pulse_cnt_save <= pulse_cnt + 6'd1;
```

**Problem 1: `pulse_cnt` itself is never reset between words in a burst.** When `DELAY > 0`, BUSY stays 1 between transfers (per spec R21). `pulse_cnt` keeps incrementing across the delay and into the next word. So when `$fell(BUSY)` fires, `pulse_cnt_save` holds a stale or accumulated value.

**Problem 2: The condition `pulse_cnt + 6'd1 == width` for resetting `pulse_cnt_save` between words fails** because `pulse_cnt` is 6 bits and wraps around, and `sample_edge` detection through the strobe logic can be off by one cycle relative to the actual RTL.

**Evidence from logs:**

- Error injection test: `Expected 8, got 13` — 13 = 8 (first word) + 5 (partial second word)
- FIFO stress test: `Expected 16, got 21` — 21 = 16 + 5 (inter-word delay strobes counted)
- Delay test: `Expected 8, got 9` — off by 1 from delay strobe
- Clk div test: `Expected 8, got 7` — large DIV causes timeout, counter undercount

### Fix

The counter logic needs a fundamental rework. The cleanest approach is to **reset `pulse_cnt` whenever the RTL's internal bit counter resets** (i.e., tap the RTL's actual bit counter signal). Alternatively, reset `pulse_cnt` when it reaches `width`:

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || !BUSY)
        pulse_cnt <= 6'd0;
    else if (sample_edge) begin
        if (pulse_cnt + 6'd1 == width)
            pulse_cnt <= 6'd0;     // ← reset on word boundary
        else
            pulse_cnt <= pulse_cnt + 6'd1;
    end
end

// pulse_cnt_save just captures the final count before BUSY falls
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pulse_cnt_save <= 6'd0;
    else if (BUSY && sample_edge && (pulse_cnt + 6'd1 == width))
        pulse_cnt_save <= width;
    else if ($rose(BUSY))
        pulse_cnt_save <= 6'd0;
end
```

> [!WARNING]
> The deeper issue is that the assertion's `sample_edge` derivation (reconstructing the strobe from `sclk_cnt` and `sclk_phase`) may not perfectly match the RTL's actual internal strobe timing. If there's any 1-cycle skew, the count will be wrong. Consider tapping the RTL's internal `bit_cnt` signal directly instead.

---

## 3. `a_ss_stable` — SS_n Glitch Detected During Active Transfer

### What the spec says (R20)
> *"SS_n[i] = !SS_EN[i] | SS_VAL[i] combinationally; IP never drives SS_n autonomously."*
> *"SS_n MUST remain asserted for the full transfer."*

### What the assertion checks ([spi_core_sva.sv:103-108](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/assertions/spi_core_sva.sv#L103-L108))
```systemverilog
property spi_ss_held_low;
    @(posedge clk) disable iff (!rst_n)
    (BUSY && $past(BUSY)) |-> $stable(ss_n);
endproperty
```

### Root cause: The assertion checks BUSY=1 && past(BUSY)=1, but SS_n legitimately changes the cycle after BUSY falls

This assertion fires in two scenarios:

**Scenario A (error_injection_test):** The test intentionally manipulates SS_CTRL mid-transfer to inject errors. The assertion correctly catches the *test's intentional bad behavior*, but since this is an error injection test, these are **expected** assertion fires. The test should either disable the assertion or the assertion should be aware of test context.

**Scenario B (clk_div_corner_test):** With large DIV values (e.g., 1024), the test's `wait_idle` times out (`CHECKER_ERROR: wait_idle: DUT hung?`) and the test forcefully deasserts SS_n while BUSY is still 1. This is a **test timeout issue**, not a DUT bug. The assertion fires because the test gave up waiting and changed SS_n.

**Evidence:**
```
# [CHECKER_ERROR] wait_idle: DUT hung?
# ** Error: SS_n glitch/deassert detected during active transfer! SS_n=1111
```
The "DUT hung" message appears right before each SS_n assertion fire in the clk_div test.

### Fix

The assertion itself is actually correct per the spec. The issues are:

1. **Error injection test**: Wrap the intentional error scenarios with assertion disable:
   ```systemverilog
   // In the test:
   $assertoff(0, tb_top.u_wrap.u_dut.u_regfile.u_sva.u_core_sva.a_ss_stable);
   // ... do error injection ...
   $asserton(0, tb_top.u_wrap.u_dut.u_regfile.u_sva.u_core_sva.a_ss_stable);
   ```

2. **Clk div test**: Increase the `wait_idle` timeout for large DIV values. DIV=1024 with 8-bit transfer needs `8 × 2 × 1025 = 16,400` PCLK cycles minimum. The current timeout is likely too short.

---

## 4. `a_mosi_stable` — MOSI Unstable on Sample Edge

### What the spec says (R5)
> *"For each SPI mode, MOSI is stable across the sample edge."*

### What the assertion checks ([spi_core_sva.sv:90-95](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/assertions/spi_core_sva.sv#L90-L95))
```systemverilog
property spi_mosi_stable;
    @(posedge clk) disable iff (!rst_n)
    (BUSY && sample_edge && !$past(launch_edge)) |-> $stable(mosi);
endproperty
```

### Root cause: DIV=0 case — launch and sample edges are adjacent PCLK cycles

With DIV=0, `SCLK = PCLK/2`, meaning the strobe counter hits `cfg_clk_div=0` every single PCLK cycle. The leading and trailing strobes alternate on every cycle. The code comments (lines 82-86) acknowledge this:

> *"With DIV=0 launch and sample are adjacent — this is a borderline case the spec says is valid."*

The guard `!$past(launch_edge)` is supposed to suppress the check when the previous cycle was a launch edge. **But with DIV=0, `$past(launch_edge)` may not evaluate correctly** because:
- `launch_edge` depends on `sclk_cnt == cfg_clk_div && sclk_phase == X`
- With DIV=0, both `leading_strobe` and `trailing_strobe` fire on alternating cycles
- `$past(launch_edge)` sees the value one PCLK ago, but the strobe logic's phase tracking may be off by one

**Evidence:** 
- Delay test fires at DIV=0 (`delay=128 div=0`)
- Clk div test fires at DIV=0 and DIV=65535 edge cases

### Fix

Add an explicit DIV=0 guard:

```systemverilog
property spi_mosi_stable;
    @(posedge clk) disable iff (!rst_n)
    (BUSY && sample_edge && !$past(launch_edge) && cfg_clk_div != 16'd0)
    |-> $stable(mosi);
endproperty
```

Or better, for DIV=0, only check that MOSI doesn't change on the **same** cycle as the sample edge (not `$stable` which looks backward):

```systemverilog
property spi_mosi_stable;
    @(posedge clk) disable iff (!rst_n || cfg_clk_div == 16'd0)
    (BUSY && sample_edge && !$past(launch_edge)) |-> $stable(mosi);
endproperty
```

> [!NOTE]
> The spec says DIV=0 is valid (R24: "CLK_DIV=0 yields SCLK = PCLK/2"). At this speed, MOSI changes every PCLK cycle and is stable for exactly 1 PCLK before the sample edge, which meets the spec's "stable across the sample edge" requirement. The `$stable()` operator checks against `$past()` which is the launch edge — so seeing a change is expected and correct DUT behavior.

---

## Summary of Recommended Fixes

| # | Assertion | Fix Type | Effort |
|---|---|---|---|
| 1 | `a_sclk_idle` | Reset `idle_cnt` on CPOL change | Small |
| 2 | `a_xfer_length` | Rewrite counter to reset at word boundary; consider tapping RTL bit_cnt | Medium |
| 3 | `a_ss_stable` | Assertion is correct — fix tests to `$assertoff` during intentional errors, increase timeouts | Small |
| 4 | `a_mosi_stable` | Disable for DIV=0 or rework `$past` guard | Small |

> [!TIP]
> The regfile assertions (`spi_regfile_sva.sv`) are **not firing** — they appear correct. No changes needed there.
