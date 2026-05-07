# SPI Master Harness — File Responsibilities & 7-Member Task Distribution

## 1. Architecture at a Glance

![Mermaid Diagram](https://kroki.io/mermaid/svg/eNqFVO1u0zAU_b-nsPIDbULd4AWQuibbuq0fa7IBilDkxDetmWsH2-m0B-A3EvAHBOI1eJ69ADwC195asrTVIh0psc_Nvef4Xk81rWYkCXcIPqbOp_57MkqDv7--fiYToKwzkuKWnFAtwRiyG47IcJSQKOwne8E7H-eebhrQKs94uW8WZLc7PiR5bQiXFnRJC2hSD9PAVHxJjcf97dReGrDaZjdYVQXa88PLBLnGUmk5tVxJYmYgxDIKJNt5LCaOek7Nl58ktjUDaTsR45bmAkhPMWhkW4UkWKLNDxpb7gndYmZV5etIVNURsABBlC5mYKymVum9Vkx0b8ucGlSX5eW8aU-nrGXhJFBB5liKaEcf3TtlBF3AKtgZ5leIBlMpyeBRVmfAmqBoeJUGIBdtScdpoKHMfHL_82Ml0CJSaWC8QD3kOTGF0pArqlm7vJM0KNQCNJ2CDz76L8evT7WqK_NkcUkUJzF6ix6aA7L78gUK-1BzLKGdsI9-UMntbebILufdj48tzqmTNM1oUWC7LnktzlkaOMnZsvottPM0uOHMzp7iDdKg5KXKsAe25xymgW9xXVd2CwWnrhDXGeMLzIjjprfwxmkglKpyWlxvYVzg3ICg6JOm0pRb_zTBrtBa6YzL9-DPbgNx46HFEeYweE4g0eh2X-FxGsvnmeC574wJlUzNufFT52uiPhspBDUGnu6R-MpdMEjVLmwtX_IwKAt6PyJXXZJzydxU1QI2_X39nghHPSz77vu3P78_kcOaC0aekVAVphF9mQYDeg0lF817A2drEnXDQbQ_Z43l13gIGH7gHM0qQeV-xcrG_puH_ZLjxGQaKqVti_L2gbJqwDXWSkdIOp1XpIs1HyJ6jbUIv48Qx4gTROL3-vh2ijhDnCMGiCFihBgjLhCTjfHxP2xZw4w=)

---

## 2. File-by-File Responsibility

### 2.1 🔒 Read-Only Harness Files (provided — **do NOT edit**)

| File | What It Is | Why It Matters |
|------|-----------|----------------|
| [apb_if.sv](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/apb_if.sv) | APB v2.0 SystemVerilog `interface` with `cb_master` and `cb_monitor` clocking blocks | Provides the typed bus that connects your APB BFM to the DUT. You drive signals via `apb.cb_master.*`. |
| [spi_if.sv](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/spi_if.sv) | SPI-side `interface` exposing SCLK, MOSI, MISO, SS_n, IRQ with `cb_slave` and `cb_mon` clocking blocks | Your SPI slave BFM drives MISO through `spi.cb_slave.miso` and observes SCLK/MOSI edges. |
| [dut_wrapper.sv](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/dut_wrapper.sv) | Module that wraps the `spi_master` DUT; exposes `u_dut.u_regfile` and `u_dut.u_core` for backdoor access and SVA bind | The grader swaps RTL via this wrapper. You `bind` SVA into `u_wrap.u_dut.u_regfile` or `u_wrap.u_dut.u_core`. |

### 2.2 📝 Student Files — What Exists vs What You Must Build

#### `tb/tb_top.sv` — Top-Level Test Orchestrator
- **Current state:** Scaffold has clock gen, reset, interface instantiation, DUT wrapper, BFM instances, SVA bind, and a `case` dispatcher for `+TESTNAME=`. Only `sanity_test` and `randomized_sanity_test` are wired.
- **Work needed:**
  - Add `\`include` lines for all 10 required test files (7 are missing)
  - Add 8 more `case` arms in the dispatcher (one per new test)
  - Possibly wire additional SVA bind points (e.g., bind into `u_core` for SPI protocol assertions)
  - May need to expose additional BFM control signals (e.g., `bfm_width`, `bfm_lsb_first`)

#### `tb/apb_master_bfm.sv` — APB Bus Functional Model
- **Current state:** Has `apb_write()` and `apb_read()` tasks. Functional.
- **Work needed:**
  - **Minimal** — the scaffold's `apb_write`/`apb_read` are sufficient for all tests
  - Optional: add a `apb_write_burst()` helper for FIFO stress scenarios, or an `apb_idle()` task

#### `tb/spi_slave_bfm.sv` — SPI Slave Responder
- **Current state:** Only supports **Mode 0, MSB-first**. Drives a fixed `miso_byte` pattern.
- **Work needed (MAJOR):**
  - Generalise to **all 4 SPI modes** (CPOL/CPHA combinations)
  - Support **LSB-first** bit ordering
  - Support **16-bit and 32-bit** transfer widths (multi-byte MISO patterns)
  - **Capture the MOSI stream** into a queue so the scoreboard can compare what the DUT sent
  - Handle **loopback mode** (when loopback is on, MISO should drive "nonsense" that the DUT ignores)
  - Add **programmable response patterns** (not just a single fixed byte)

#### `env/ref_model.sv` — Reference Model + Scoreboard
- **Current state:** Only predicts a single 8-bit transfer. Has `check_rx()` and `check_reg()` methods.
- **Work needed (MAJOR):**
  - **Full register file model**: track all 9 registers with correct reset values, R/W masks, and W1C logic for `INT_STAT`
  - **TX/RX FIFO model**: 8-deep FIFOs with `full`/`empty`/`ovf` flag tracking
  - **SPI transfer predictor**: model bit-serial shifting for all modes/widths/orderings
  - **Interrupt predictor**: `IRQ = |(INT_STAT & INT_EN)` with sticky flags
  - **SCLK timing predictor**: predict frequency based on `CLK_DIV`
  - **Check functions** for every verification scenario (register values, FIFO depths, interrupt states, etc.)

#### `env/coverage.sv` — Functional Coverage Collector
- **Current state:** Only has `cg_config` covering mode × width cross. Nowhere near 85%.
- **Work needed (MAJOR):**
  - Add covergroup for **CLK_DIV corners** (bins: 0, 1, 2, 3, 255, 1024, 65535, random)
  - Add covergroup for **FIFO occupancies** (bins: empty, 1, 4, 7, full) for both TX and RX
  - Add covergroup for **DELAY bins** (0, 1, ≥128)
  - Add covergroup for **interrupt state combinations** (5 sources, 32 combinations)
  - Add covergroup for **MSB/LSB-first** cross with mode and width (24 combinations total)
  - Add covergroup for **loopback on/off**
  - Add covergroup for **slave select patterns** (which SS_n lines are asserted)
  - Add covergroup for **register access** (read/write hits on all 9 registers + reserved offsets)
  - Goal: **≥ 85% on golden RTL**

#### `sequences/stim_lib.sv` — Reusable Transaction Classes
- **Current state:** Single `spi_txn` class with basic random fields and constraints.
- **Work needed:**
  - Add **specialised transaction classes** or constraint layers for each test scenario:
    - `spi_fifo_txn` (constrain for burst/stress patterns)
    - `spi_interrupt_txn` (constrain to trigger specific interrupt sources)
    - `spi_clkdiv_txn` (constrain to corner div values)
  - Add **configuration transaction** class for register setup sequences
  - Add **helper functions** for common sequences (e.g., "reset → configure → single transfer")

#### `assertions/spi_sva.sv` — SystemVerilog Assertions
- **Current state:** Only 2 assertions (IRQ aggregate, IRQ off when disabled). Bound to `u_regfile` only.
- **Work needed (MAJOR):**
  - **APB protocol assertions**: PENABLE only when PSEL=1, zero-wait-state (PREADY always 1)
  - **SCLK idle level**: matches CPOL when not transferring
  - **MOSI stability**: stable across the sample edge defined by CPOL/CPHA
  - **FIFO bounds**: pointer never exceeds depth of 8
  - **SS_n stability**: doesn't toggle autonomously during a transfer
  - **IRQ combinational logic**: `IRQ == |(INT_STAT & INT_EN)` (already exists, extend)
  - **Transfer length**: exactly `WIDTH` SCLK cycles per transfer
  - **W1C race**: new hardware event preserved if W1C happens on the same cycle
  - May need a **second SVA module** bound to `u_wrap.u_dut.u_core` for SPI-side assertions

#### `tests/` — The 10 Required Tests

| # | Test Name | Status | Verif Plan TC | Requirements | What It Must Do |
|---|-----------|--------|---------------|--------------|-----------------|
| 1 | `sanity_test.sv` | ✅ Exists | — | R1-R7 | Single mode-0, 8-bit transfer. Already works. |
| 2 | `reg_access_test.sv` | ❌ Missing | TC_01 | R1, R2, R3, R22, R23 | Read reset values of all 9 regs; write-read-back every R/W reg; verify reserved offsets return 0; test CTRL.EN=0 resets shifter/FIFOs. |
| 3 | `mode_coverage_test.sv` | ❌ Missing | TC_02 | R4, R5, R6, R7 | Cross all 4 modes × 3 widths × 2 orderings = **24 transfers**, verify each. |
| 4 | `width_coverage_test.sv` | ❌ Missing | TC_02 | R6, R7 | Edge-case width boundaries (8→16→32), verify correct bit count on SCLK. |
| 5 | `fifo_stress_test.sv` | ❌ Missing | TC_04 | R9-R15 | Push 8 entries to fill TX, pop 8 from RX, overflow both, verify flags/data. |
| 6 | `interrupt_test.sv` | ❌ Missing | TC_05 | R16, R17, R18 | Trigger each of 5 interrupts, mask/unmask, W1C clear, W1C race condition. |
| 7 | `clk_div_corner_test.sv` | ❌ Missing | TC_03 | R8, R21 | DIV = 0, 1, small, ≥1024; measure SCLK frequency against expected. |
| 8 | `loopback_test.sv` | ❌ Missing | TC_06 | R19 | CTRL.LOOPBACK=1; drive garbage on MISO; verify RX == TX. |
| 9 | `delay_transfer_test.sv` | ❌ Missing | TC_03 | R24, R25 | DELAY > 0 inserts idle SCLK cycles between consecutive transfers. |
| 10 | `error_injection_test.sv` | ❌ Missing | TC_04 | R9-R15 | Write TX when full, read RX when empty, illegal width, reserved offsets. |

#### `Makefile`
- **Current state:** Fully functional scaffold. Already lists all 10 tests in `REGRESSION_TESTS`.
- **Work needed:** Keep `REGRESSION_TESTS` updated if you add extra tests; no other changes unless you add new source files to `ENV_SRCS`, `SEQ_SRCS`, or `ASSERT_SRCS`.

#### `docs/` — Required Documentation
- **Completely missing.** Must create:
  - `test_plan.pdf` — formal test plan (your verification plan converted to PDF)
  - `final_report.pdf` — results, bug tracking, lessons learned
  - `coverage_report.pdf` — exported after `make cov`

---

## 3. Dependency Graph

![Mermaid Diagram](https://kroki.io/mermaid/svg/eNpdjztPAzEMgHd-hZWhKsNFLRTYkIDjMTBVbFEV5XLONVLuEtnp9e-ThpeKJz8-f7JdiEe7N5ThfXsBJR6UWEvg7EcdfCd5hmUmM7Gx2ceJL8UOmuYeWiU2zZ2ED-QMzgdkWK5XkEt5YqrqUYmrokpeczAz6s6N1WdCgA2Mscc_XV14UuJaAqHTp2GosDsUOhH23uZI5_yzEjcSbJyRzIC_7toYKB7SP_-LErffB83mC2dG-nmsMq9KlLdyp3NMFek9J5PtHgmOnvw0nDvbmr8pscWBkLm4YAFttCx2n0nnZ7s=)

> [!IMPORTANT]
> The **slave BFM**, **ref model**, and **stim_lib** are infrastructure that almost ALL tests depend on. These **must be completed first** (or at least stubbed with mode-0 support) before test writers can work independently.

---

## 4. 7-Member Task Assignment — All Hands, Both Phases

> [!IMPORTANT]
> **All 7 members work on Phase 1 together, then all 7 shift to Phase 2.**
> Deadline: **1 week (Wed May 7 → Tue May 13, 2026)**.

---

### Phase 1 — Infrastructure (Wed May 7 – Fri May 9) · 3 days

All 7 members focus on building the shared infrastructure in parallel. Members are **paired** on the heaviest components to share the load.

| Pair | Role | Files Owned | Responsibility |
|------|------|-------------|----------------|
| **M1 + M2** | SPI Slave BFM Team | `tb/spi_slave_bfm.sv` | **Extend the SPI slave BFM to support the full SPI protocol space.** Currently only Mode 0 / MSB-first / 8-bit is supported. The pair must add support for all 4 SPI modes (CPOL×CPHA), LSB-first bit ordering, 16-bit and 32-bit transfer widths, MOSI capture into a queue for scoreboard comparison, and programmable MISO response patterns. Must also handle the loopback case (drive don't-care on MISO). The BFM must expose new control ports (`width`, `lsb_first`) and rename `miso_byte` → `miso_pattern [31:0]` per the API contract. **Suggested split:** M1 handles Mode 0/1 (CPOL=0) + MOSI capture logic; M2 handles Mode 2/3 (CPOL=1) + LSB-first ordering + loopback behaviour. |
| **M3 + M4** | Reference Model & Scoreboard Team | `env/ref_model.sv` | **Build a cycle-accurate golden model of the entire SPI master.** This includes modelling all 9 registers with their reset values, R/W masks, and W1C behaviour; maintaining shadow TX/RX FIFOs (8-deep) with full/empty/overflow flag prediction; predicting the RX data for any transfer configuration (mode, width, ordering, loopback); predicting interrupt status (`INT_STAT`) and IRQ output based on hardware events and masking; and predicting SCLK period from `CLK_DIV`. All `check_*()` and `predict_*()` methods in the API contract must be implemented. **Suggested split:** M3 handles register file model + FIFO model + `check_status()` / `check_reg()`; M4 handles SPI transfer predictor + interrupt predictor + `predict_transfer()` / `predict_interrupt()` / `predict_w1c()`. |
| **M5 + M6** | Coverage + Stimulus + Integration Team | `env/coverage.sv`, `sequences/stim_lib.sv`, `tb/tb_top.sv`, `Makefile` | **Build all coverage infrastructure, stimulus classes, and wire the testbench together.** Coverage side: add covergroups for CLK_DIV corners, FIFO occupancy, interrupt combinations, delay bins, slave-select patterns, register access, and loopback mode. Extend `cg_config` to cross mode × width × ordering × loopback. Implement all `sample_*()` tasks from the API contract. Stimulus side: add helper methods to `spi_txn` (`ctrl_word()`, `num_bits()`, `tx_masked()`), create `reg_txn`, `fifo_txn`, and `clkdiv_txn` classes. Integration side: add `\`include` directives for all new test files, `case` arms in the dispatcher, wire new BFM ports (`bfm_width`, `bfm_lsb_first`), widen `bfm_pattern` to 32 bits, add SVA `bind` for `u_core`, and keep `Makefile` variables updated. Run `make compile` continuously. **Suggested split:** M5 focuses on coverage + stim lib; M6 focuses on tb_top integration + Makefile + continuous compile checks. |
| **M7** | SVA & Assertions Lead | `assertions/spi_sva.sv` (+ `spi_core_sva.sv`) | **Write all mandatory SystemVerilog Assertions for protocol and design rule checking.** The test plan and verification plan already exist (`docs/test_plan.html`, `docs/verification_plan.html`) — M7 does NOT need to recreate them. SVA work: add APB protocol assertions (PENABLE gating, zero-wait-state PREADY), SCLK idle-level check against CPOL, MOSI stability on sample edge, FIFO pointer bounds (≤8), SS_n stability during active transfers, transfer length (exactly WIDTH cycles), W1C race-condition preservation, and SS combinational logic. Fix the existing `a_irq_agg` to include `INT_EN` masking. Create a second SVA module bound to `u_core` for SPI-side assertions. M7 has the lightest code volume among the pairs, so they should also serve as a **floating helper** available to assist any pair that falls behind. |

> [!TIP]
> **Phase 1 exit criterion:** By end of Friday May 9, all infrastructure files must compile cleanly together (`make compile` passes), and a `sanity_test` run using the new BFM, ref model, and coverage must produce `[TEST_PASSED]`.

---

### Phase 2 — Tests & Final Integration (Sat May 10 – Tue May 13) · 4 days

All 7 members now pivot to writing the 9 remaining tests, integration debugging, and documentation. Test assignments leverage each member's Phase 1 domain expertise.

| Member | Phase 1 Role (for context) | Tests Owned | Responsibility |
|--------|---------------------------|-------------|----------------|
| **M1** | BFM Team (Modes 0/1) | `mode_coverage_test.sv`, `loopback_test.sv` | **Write the tests that exercise the full SPI protocol space.** `mode_coverage_test` must iterate over all 4 modes × 3 widths × 2 orderings (24 configurations), perform a transfer for each, and verify RX data against the ref model. `loopback_test` must enable CTRL.LOOPBACK, drive don't-care on MISO, and confirm RX matches TX for multiple widths/orderings. Both tests must call the appropriate `sample_config()` / `sample_loopback()` coverage methods. |
| **M2** | BFM Team (Modes 2/3) | `width_coverage_test.sv` | **Write the test that verifies transfer-width edge cases.** Perform transfers at 8-bit, 16-bit, and 32-bit widths, verify the exact number of SCLK cycles per transfer, and confirm RX data is correctly masked to the active width. Call `sample_config()` for each configuration. M2's BFM expertise is critical for debugging width-related MISO/MOSI mismatches. |
| **M3** | Ref Model Team (Regs+FIFOs) | `fifo_stress_test.sv`, `error_injection_test.sv` | **Write the tests that stress the data path and inject error conditions.** `fifo_stress_test` must fill the TX FIFO to capacity (8 entries), trigger transfers to fill RX, verify all flag transitions (empty→full, overflow), and confirm data integrity across the FIFOs. `error_injection_test` must attempt illegal operations: write TX when full, read RX when empty, write reserved register offsets, and set illegal width encodings — then verify the DUT handles each gracefully (correct flags, no hangs). Both tests must call `sample_fifo()`. M3's FIFO model knowledge makes them ideal for these tests. |
| **M4** | Ref Model Team (Transfers+IRQ) | `interrupt_test.sv` | **Write the test that exercises the full interrupt subsystem.** Trigger each of the 5 interrupt sources individually, verify `INT_STAT` and `IRQ` against predictions. Test masking (enable/disable each source via `INT_EN`), W1C clearing (write-1-to-clear each flag), and the W1C race condition (hardware event on the same cycle as a W1C write must keep the flag set). Call `sample_interrupt()` for coverage. M4 built the interrupt predictor, so they are best positioned to write and debug this test. |
| **M5** | Coverage + Stim Team | `clk_div_corner_test.sv`, `delay_transfer_test.sv` | **Write the tests that verify timing-related features.** `clk_div_corner_test` must configure CLK_DIV to corner values (0, 1, 2, 3, 255, 1024, 65535), perform a transfer at each, measure the resulting SCLK period, and compare against the formula via `check_sclk_period()`. `delay_transfer_test` must configure DELAY > 0, perform consecutive transfers, measure the idle gap between them, and verify via `check_delay()`. Both tests must call the corresponding `sample_*()` coverage methods. M5 wrote the `clkdiv_txn` constraints so they already know the corner values. |
| **M6** | Integration Team | `reg_access_test.sv` | **Write the register-access test and perform continuous integration.** `reg_access_test` must read all 9 registers after reset and verify default values, write-then-read-back every R/W register, verify reserved offsets return 0, and confirm that clearing CTRL.EN resets the shifter and FIFOs. Call `sample_register()` for coverage. Additionally, M6 continues as the integrator: keeping `tb_top.sv` updated as each test lands and running `make regress` to catch integration issues across the full suite. |
| **M7** | SVA + Docs | `docs/final_report.pdf`, `docs/coverage_report.pdf` | **Complete all documentation deliverables.** Collect each member's description of their tests and findings, assemble the final report covering: methodology, test descriptions, bugs found, coverage results, and lessons learned. After the final regression, export the coverage database via `make cov` and produce `coverage_report.pdf`. Ensure all three required documents (`test_plan.pdf`, `final_report.pdf`, `coverage_report.pdf`) are in the `docs/` directory. Also available to support any team needing help debugging SVA-related test failures. |

> [!TIP]
> **Phase 2 exit criterion:** By end of Tuesday May 13, `make regress` passes all 10 tests with `[TEST_PASSED]`, functional coverage ≥ 85%, all SVA assertions are clean on golden RTL, and all 3 docs are in `docs/`.

---

### Cross-Cutting Responsibilities (Both Phases)

| Responsibility | Owner(s) | Notes |
|----------------|----------|-------|
| `tb/tb_top.sv` updates (includes + dispatcher) | **M6** (primary), anyone finishing a test | Mechanical task — add `\`include` + `case` arms as tests land |
| `Makefile` updates | **M6** | If new source files need adding to `ENV_SRCS` etc. |
| `docs/test_plan.pdf` | ✅ **Already exists** (`test_plan.html` + `verification_plan.html`) | Convert existing HTML to PDF before submission (any member) |
| `docs/final_report.pdf` | **M7** (assembler) + **All** (each writes their section) | Each member writes their section; M7 assembles |
| `docs/coverage_report.pdf` | **M5** (export) + **M7** (format) | Export from `make cov` output after final regression |
| Integration & regression debugging | **M6** (lead) + **M1, M2, M3** (support) | BFM + ref_model mismatches cause most failures |
| Code review & API contract enforcement | **All** | No one changes a method signature without team agreement |

---

## 5. One-Week Timeline

| Day | Date | Focus | Milestone |
|-----|------|-------|-----------|
| **Day 1** | Wed May 7 | 🔧 Phase 1 kickoff — all pairs start infrastructure | API contract reviewed, skeleton files created, pairs aligned on internal split |
| **Day 2** | Thu May 8 | 🔧 Phase 1 — core implementation | BFM supports all modes; ref model has register + FIFO + transfer models; covergroups coded; stim classes done; SVA assertions written |
| **Day 3** | Fri May 9 | 🔧 Phase 1 wrap-up — integration & smoke test | `make compile` passes; `sanity_test` runs with new infra; test plan PDF submitted; **Phase 1 done** |
| **Day 4** | Sat May 10 | 🧪 Phase 2 kickoff — all members start writing tests | Each member has their test(s) skeleton compiling |
| **Day 5** | Sun May 11 | 🧪 Phase 2 — test implementation & debug | All tests self-checking; iterative debug against ref model |
| **Day 6** | Mon May 12 | 🧪 Phase 2 — full regression & coverage closure | `make regress` → target all 10 `[TEST_PASSED]`; coverage gaps identified and closed |
| **Day 7** | Tue May 13 | 📄 Final polish — docs, coverage export, submission | `final_report.pdf` + `coverage_report.pdf` done; final `make regress` clean; **submit** |

---

## 6. Quick Reference: How to Add a New Test

Every new test file follows the same 4-step pattern:

1. **Create** `tests/<test_name>.sv` with a class containing a `static task run(ref spi_ref_model, ref spi_coverage_col)` method
2. **Add** `` `include "tests/<test_name>.sv" `` near the top of `tb/tb_top.sv`
3. **Add** a `case` arm in `tb_top`'s dispatcher:
   ```systemverilog
   "<test_name>" : <test_name>::run(u_ref, u_cov);
   ```
4. **Verify** the test name is already in `Makefile:REGRESSION_TESTS` (it should be — all 10 are pre-listed)

> [!TIP]
> Look at [sanity_test.sv](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/tests/sanity_test.sv) and [randomized_sanity_test.sv](file:///d:/Kolya/Senior-1/Second%20Semester/Verification/Project/final_project_student/harness/examples/sv_only/tests/randomized_sanity_test.sv) as templates. Every test follows the same `configure BFM → predict → drive APB → poll BUSY → check RX` flow.

---

## 7. Key Grading Contract Reminders

| Rule | Source |
|------|--------|
| Every test prints exactly one `[TEST_PASSED]` or `[TEST_FAILED]` line | Grading §3 |
| Mismatches print `[SCOREBOARD_ERROR] ...` | Grading §3 |
| SVA failures print `[ASSERTION_ERROR] ...` | Grading §3 |
| Functional coverage ≥ 85% **and** code coverage ≥ 85% on golden RTL | Grading §4 |
| Total regression ≤ 10,000 runs (`|REGRESSION_TESTS| × REGRESSION_SEEDS`) | Grading §5 |
| **Per-bug regression budget ≤ 5 minutes wall time** (all tests × all seeds must complete in 300s) | Grading §5 |
| Test names in `REGRESSION_TESTS` are **student-defined** — no mandatory names, but names must match `case` arms exactly | Grading §9 |
| SVA must be in a `bind`-ed module, NOT inline in the DUT | Grading §9 |
| `DUT_SRCS` variable must NOT be hardcoded — grader overrides it with buggy RTL | Grading §2 |
| Cap `CLK_DIV` in tests — large DIV burns simulation time and may bust the 5-min budget | Grading §5 note |
| `docs/test_plan.pdf`, `docs/final_report.pdf`, `docs/coverage_report.pdf` must all exist | Grading §1, §8 |

---

## 8. Requirement Traceability Matrix (R1–R25 → Tests × Coverage × SVA)

This table maps every spec requirement to which test(s), coverage group(s), and assertion(s) verify it. Use this to confirm **no requirement is left uncovered**.

| Req | Requirement Description | Verified By Test(s) | Coverage | SVA |
|-----|------------------------|--------------------|---------|---------|
| **R1** | APB reads/writes return last written value (masked by RO bits) | `reg_access_test`, `sanity_test` | `cg_register` | `a_apb_penable`, `a_apb_zero_ws` |
| **R2** | All registers return specified reset values after PRESETn | `reg_access_test` | `cg_register` | — |
| **R3** | CTRL.EN=0 holds shifter/FIFOs in reset; SCLK at CPOL idle; SS_n high | `reg_access_test` | — | `a_sclk_idle` |
| **R4** | SCLK idle polarity matches CPOL before/between/after transfers | `mode_coverage_test`, `sanity_test` | `cg_config` (mode bins) | `a_sclk_idle` |
| **R5** | MOSI stable across sample edge; changes on launch edge | `mode_coverage_test` | `cg_config` (mode bins) | `a_mosi_stable` |
| **R6** | MSB-first shifts bit[WIDTH-1] first; LSB-first shifts bit[0] first | `mode_coverage_test`, `width_coverage_test` | `cg_config` (ordering bins) | `a_xfer_length` |
| **R7** | Transfer lasts exactly WIDTH SCLK cycles; BUSY deasserts after last sample | `width_coverage_test`, `mode_coverage_test`, `sanity_test` | `cg_config` (width bins) | `a_xfer_length` |
| **R8** | SCLK freq = PCLK / (2×(DIV+1)) for all DIV ∈ [0, 65535] | `clk_div_corner_test` | `cg_clkdiv` | — |
| **R9** | TX_DATA writes accepted while !TX_FULL, pushed in FIFO order | `fifo_stress_test` | `cg_fifo` (TX occupancy) | `a_fifo_bounds` |
| **R10** | RX_DATA reads pop RX FIFO in FIFO order when !RX_EMPTY | `fifo_stress_test` | `cg_fifo` (RX occupancy) | `a_fifo_bounds` |
| **R11** | TX FIFO depth = 8; TX_FULL asserts on 8th entry | `fifo_stress_test` | `cg_fifo` (TX full bin) | `a_fifo_bounds` |
| **R12** | RX FIFO depth = 8; RX_FULL asserts on 8th received entry | `fifo_stress_test` | `cg_fifo` (RX full bin) | `a_fifo_bounds` |
| **R13** | TX write while TX_FULL=1 → discard + TX_OVF flag | `error_injection_test`, `fifo_stress_test` | `cg_fifo`, `cg_interrupt` | — |
| **R14** | RX push while RX_FULL=1 → discard + RX_OVF flag | `error_injection_test`, `fifo_stress_test` | `cg_fifo`, `cg_interrupt` | — |
| **R15** | RX read while RX_EMPTY → returns 0, does NOT set RX_OVF | `error_injection_test` | `cg_fifo` (RX empty bin) | — |
| **R16** | IRQ = |(INT_STAT & INT_EN); INT_EN does not gate status capture | `interrupt_test` | `cg_interrupt` | `a_irq_agg` |
| **R17** | INT_STAT is W1C: writing 1 clears bit; 0 has no effect | `interrupt_test` | `cg_interrupt` | `a_w1c_race` |
| **R18** | W1C race: event + W1C on same PCLK → bit stays 1 | `interrupt_test` | `cg_interrupt` | `a_w1c_race` |
| **R19** | Loopback: MOSI → RX internally; external MISO ignored | `loopback_test` | `cg_config` (loopback bin) | — |
| **R20** | SS_n[i] = !SS_EN[i] \| SS_VAL[i] combinationally; IP never toggles SS_n | `mode_coverage_test`, `sanity_test` | `cg_ss` | `a_ss_stable`, `a_ss_combo` |
| **R21** | DELAY SCLK half-cycles idle between consecutive transfers | `delay_transfer_test` | `cg_delay` | — |
| **R22** | PSLVERR=0, PREADY=1 for every access (zero wait states) | `reg_access_test` | `cg_register` | `a_apb_zero_ws` |
| **R23** | Reserved offsets (≥0x24) read 0; writes ignored | `reg_access_test`, `error_injection_test` | `cg_register` (reserved bin) | — |
| **R24** | CLK_DIV=0 yields SCLK = PCLK/2 (no divide-by-zero) | `clk_div_corner_test` | `cg_clkdiv` (DIV=0 bin) | — |
| **R25** | DIV, MODE, WIDTH, LSB_FIRST sampled at transfer start, held for duration | `clk_div_corner_test`, `mode_coverage_test` | `cg_clkdiv`, `cg_config` | — |

> [!NOTE]
> **Gap check:** The test plan covers R1–R25 with no gaps. Every requirement has at least one test, and most have a dedicated coverage bin or SVA assertion. Two requirements (R3, R25) rely primarily on indirect verification — R3 through `reg_access_test` observing FIFO/shifter reset side-effects, and R25 through `clk_div_corner_test` verifying frequency doesn't change mid-transfer.

> [!WARNING]
> **Test plan discrepancies found vs. the harness task distribution:**
> - `reg_access_test`: The existing test plan maps it to **R1, R2** only, but it should also cover **R3** (EN=0 reset), **R22** (PREADY=1), and **R23** (reserved offsets). The harness tasks already include these — make sure the test implementation covers all five.
> - `fifo_stress_test`: Test plan maps to **R9, R10, R11, R12** — correct but should also target **R13, R14** (overflow flags) which are shared with `error_injection_test`.
> - `clk_div_corner_test`: Test plan maps to **R8, R24, R25** — correct. Task distribution previously listed R8, R21 which was wrong (R21 is delay, not clk_div). Fixed in this version.
