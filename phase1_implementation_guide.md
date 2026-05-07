# Phase 1 — Deliverables, Structures, and Requirements

This document strictly defines the architectural deliverables and functional requirements that each pair must fulfill by the end of Phase 1. It defines *what* must be built, the exact SystemVerilog structures to create, and the API signatures they must hand off to the Phase 2 test writers.

---

## 🛠️ Pair 1: M1 + M2 (SPI Slave BFM)
**Target File:** `tb/spi_slave_bfm.sv`

### Final Deliverable
A fully generalized SPI slave bus functional model that accurately responds to any valid SPI transaction initiated by the DUT and records the transmitted data for verification.

### Expected API Signature (Hand-off to Phase 2)
The test writers in Phase 2 will expect exactly this module signature to be available so they can wire the testbench top:
```systemverilog
module spi_slave_bfm (
    spi_if.slave spi,
    input logic [1:0] mode,          // Driven by test to match DUT CPOL/CPHA
    input logic [1:0] width,         // Driven by test to match DUT width
    input logic lsb_first,           // Driven by test to match DUT bit ordering
    input logic [31:0] miso_pattern, // The response data the BFM will inject
    output logic [31:0] captured_mosi// The data the BFM observed from the DUT
);
```

### Requirements Checklist
- [ ] **Mode Support:** The BFM must support transactions in all 4 SPI Modes (CPOL 0/1, CPHA 0/1).
- [ ] **Variable Widths:** The BFM must support transfer widths of 8 bits, 16 bits, and 32 bits.
- [ ] **Bit Ordering:** The BFM must support both MSB-first and LSB-first serialization and deserialization.
- [ ] **MISO Generation:** The BFM must accept a 32-bit testbench-provided pattern and drive it onto the MISO line accurately according to the current width and bit-ordering settings.
- [ ] **MOSI Capture:** The BFM must accurately capture the data driven by the master on the MOSI line and expose the final 32-bit word back to the testbench.
- [ ] **Loopback Tolerance:** The BFM must operate correctly even when the master is in loopback mode (i.e., it must still capture MOSI correctly even though its own MISO drive is being ignored by the DUT).

---

## 🧠 Pair 2: M3 + M4 (Reference Model & Scoreboard)
**Target File:** `env/ref_model.sv`

### Final Deliverable
A cycle-accurate golden predictor that maintains the expected state of the entire SPI master and exposes verification hooks for the testbench.

### Expected API Signature (Hand-off to Phase 2)
The test writers in Phase 2 will instantiate this class and call these exact methods during their test sequences to verify the DUT:
```systemverilog
class spi_ref_model;
    // Mutators (Called by test to update predictor state)
    function void predict_apb_write(bit [31:0] addr, bit [31:0] data);
    function void predict_apb_read(bit [31:0] addr);
    function void predict_spi_transfer(bit [31:0] actual_bfm_miso);
    
    // Checkers (Called by test to assert DUT correctness)
    function void check_status(bit [31:0] actual_status);
    function void check_reg(string reg_name, bit [31:0] expected, bit [31:0] actual);
    function void check_irq(bit actual_irq);
    function void check_rx_data(bit [31:0] actual_rx_data);
endclass
```

### Requirements Checklist
- [ ] **Register Modeling:** Accurately model the state of all 9 APB registers. This includes enforcing read-only fields, reserved bit masks, and reset values.
- [ ] **FIFO Modeling:** Accurately track the depth (0 to 8) and contents of both the TX and RX FIFOs.
- [ ] **Status Flag Prediction:** Accurately predict the exact cycle when `TX_FULL`, `TX_EMPTY`, `RX_FULL`, and `RX_EMPTY` flags assert and deassert based on FIFO operations.
- [ ] **Data Path Prediction:** Given a BFM response pattern, the model must accurately predict the final 32-bit word that will land in the `RX_DATA` register, factoring in the current width, bit-ordering, and loopback state.
- [ ] **Interrupt Prediction:** Accurately predict the state of the 5 `INT_STAT` flags based on hardware events (overflows, transfer completions).
- [ ] **IRQ Aggregation:** Continuously predict the state of the physical `IRQ` output by applying the `INT_EN` mask to the `INT_STAT` register.
- [ ] **W1C Race Condition:** Accurately predict the outcome of Requirement R18 (when a hardware event and a software W1C write occur on the exact same cycle, the hardware event must take precedence).

---

## 📊 Pair 3: M5 + M6 (Coverage, Stimulus, Integration)
**Target Files:** `env/coverage.sv`, `sequences/stim_lib.sv`, `tb/tb_top.sv`

This pair is responsible for three distinct architectural components.

### 1. Stimulus Library (`stim_lib.sv`)

#### Final Deliverable
**The Goal:** Build a reusable, object-oriented library that lets test files read like plain English by hiding all the complex APB bus writes. It acts as the primary API for all mandatory test programs, abstracting away low-level APB bus timing and register packing.

**Part 1: The Data Object (`spi_txn`)**
Extend the starter class to serve as a single "fat transaction" holding both configuration settings (mode, width, divider) and data payloads. Add constraints to prevent illegal states (like reserved widths) and restrict timing variables to sane operational ranges. It also needs a function to correctly pack the bits for the 32-bit CTRL register.

**Part 2: The Action Macros (`spi_sequence_lib`)**
Create a class of purely static tasks that take `spi_txn` objects and execute the necessary sequence of APB writes/reads via the global hierarchical BFM (`tb_top.u_apb_bfm`).
**Required Tasks:** You must write macros to: Configure the DUT, Target specific SS lanes, Push TX bursts (single & burst), Pop RX bursts, Wait for the DUT to go idle, Clear interrupts, and purposely inject bus errors.

#### Expected API Signature
```systemverilog
class spi_txn;
    rand bit [1:0]  mode, width;
    rand bit        lsb_first, loopback;
    rand bit [15:0] clk_div;
    rand bit [7:0]  delay_cfg;
    rand bit [31:0] tx_data;
    
    constraint c_legal_width;
    constraint c_sane_timing;
    
    function bit [31:0] pack_ctrl_word();
endclass

class spi_sequence_lib;
    static task configure_dut(spi_txn txn);
    static task target_ss(bit [3:0] ss_ctrl);
    static task push_single(spi_txn txn);
    static task push_burst(spi_txn txn_q[$]);
    static task pop_rx_burst(output bit [31:0] rx_q[$]);
    static task wait_idle();
    static task clear_interrupts(output bit [31:0] int_stat);
    static task inject_error(bit [7:0] addr, bit [31:0] data);
endclass
```

#### Requirements Checklist
- [ ] **Transaction Data Class:** Provide the `spi_txn` class containing constrained-random fields for all valid SPI configurations and a `pack_ctrl_word()` method.
- [ ] **Configuration Macro:** Write to `CLK_DIV`, `DELAY`, `INT_EN`, and `CTRL`.
- [ ] **Targeting Macro:** Assert/de-assert Slave Select lanes via `SS_CTRL`.
- [ ] **Transmit Macros:** Tasks for single-word pushes and burst pushes to `TX_DATA`.
- [ ] **Receive Macro:** Poll `STATUS` and harvest data from `RX_DATA` into an output queue.
- [ ] **Synchronization & Interrupt Macros:** Tasks to wait for `BUSY` to clear and a task to read/write-1-clear `INT_STAT`.
- [ ] **Error Injection Macro:** Write arbitrary data to reserved register offsets.

### 2. Functional Coverage (`coverage.sv`)

#### Final Deliverable
A functional coverage model to prove test completeness against the grading rubric. The test writers in Phase 2 will instantiate this to record their progress toward the 85% coverage goal.

#### Expected API Signature
```systemverilog
class spi_coverage_col;
    // Hooks called by tests at the end of transfers or configuration steps
    function void sample_config(bit [1:0] mode, bit [1:0] width, bit lsb_first, bit loopback);
    function void sample_clkdiv(bit [15:0] div);
    function void sample_fifo(int tx_occ, int rx_occ);
    function void sample_delay(bit [7:0] delay);
    function void sample_interrupt(bit [4:0] int_stat, bit [4:0] int_en);
    function void sample_ss(bit [3:0] ss_pattern);
    function void sample_register(bit [7:0] addr, bit is_write);
endclass
```

#### Requirements Checklist
- [ ] **Configuration Coverage:** Provide `cg_config` to hit all 24 required combinations of SPI mode (0-3) × width (8, 16, 32) × ordering (MSB, LSB).
- [ ] **Corner Case Coverage:** Provide `cg_clkdiv` to explicitly hit the DIV corner values: 0, 1, 2, 3, 255, 1024, 65535, and random values.
- [ ] **FIFO Coverage:** Provide `cg_fifo` to hit TX/RX occupancy states: empty, 1, 4, 7, and full (10 total bins across 2 FIFOs).
- [ ] **Delay Coverage:** Provide `cg_delay` to hit inter-transfer delays of 0, 1, and ≥128.
- [ ] **Interrupt Coverage:** Provide `cg_interrupt` to hit the 32 combination bins for the 5 interrupt source states.
- [ ] **Loopback Coverage:** Provide `cg_loopback` to hit loopback on/off states.
- [ ] **Slave Select Coverage:** Provide `cg_ss` to cover all slave select patterns (which SS_n lanes are asserted, including multi-slave scenarios).
- [ ] **Register Access Coverage:** Provide `cg_register` tracking read/write hits on all 9 registers plus reserved offsets.

### 3. Top-Level Integration (`tb_top.sv`)

#### Final Deliverable
A successfully compiling top-level testbench that wires the expanded BFM, Reference Model, Coverage models together, and can dynamically dispatch required tests based on arguments.

#### Expected API Signature
*(No specific external API required; this is the top-level testbench module executed by the simulator).*

#### Requirements Checklist
- [ ] **Integration:** Instantiate and wire the expanded APB BFM, SPI BFM, Reference Model, and Coverage models into the `tb_top` module.
- [ ] **Test Dispatcher:** Implement the logic in `tb_top.sv` that selects and executes the correct test sequence based on the `+TESTNAME=` simulator argument.
- [ ] **Compilation:** Maintain the Makefile to ensure that all new files compile cleanly without errors.

---

## 🛡️ M7 (SVA & Assertions)
**Target Files:** `assertions/spi_sva.sv`, `assertions/spi_regfile_sva.sv`, `assertions/spi_core_sva.sv`

### Module Setup & Signal Tapping
To keep things simple and organized, the assertion environment is split into two files that match the hardware:
- **`spi_regfile_sva.sv`**: Put assertions related to the APB bus, registers, and FIFOs here.
- **`spi_core_sva.sv`**: Put assertions related to the SPI protocol (SCLK, MOSI, MISO) here.
- **`spi_sva.sv` (The Wrapper)**: This file combines both modules and is already bound to the DUT in `tb_top.sv`.

**Your main integration task:** The skeleton files don't have all the ports you will need. When you write an assertion that needs an internal hardware signal (like a FIFO pointer or an internal state), just add that signal as a port to your SVA module and pass it up through the `spi_sva.sv` wrapper. **Do not modify `tb_top.sv` yourself.** Instead, coordinate with M6 (Integration) to update the `bind` statement in `tb_top.sv` to tap the required signals.

### Final Deliverable
A comprehensive suite of concurrent SystemVerilog Assertions bound directly to the DUT's internal interfaces to continuously monitor APB protocol compliance, SPI state behaviors, FIFO limits, and interrupt logic rules. The assertions must specifically target 100% pass rate on the golden RTL.

### Expected API Signature (Hand-off to Phase 2 Integration)
M6 (Integration) will need these exact module signatures (plus whatever internal taps M7 decides to add) to exist so they can successfully `bind` them to the DUT in `tb_top.sv`:

```systemverilog
// In spi_sva.sv (Wrapper)
module spi_sva(
    // ... APB, SPI, and tapped internal signals ...
);
    spi_regfile_sva u_regfile_sva (/* ... */);
    spi_core_sva u_core_sva (/* ... */);
endmodule

// In spi_regfile_sva.sv
module spi_regfile_sva (
    input logic PCLK, PRESETn,
    input logic PSEL, PENABLE, PREADY, PSLVERR,
    input logic IRQ,
    input logic ctrl_en,
    input logic [4:0] INT_STAT, INT_EN
    // + Add required internal taps like FIFO pointers
);
    // Assertions related to `apb_regfile` inside here
endmodule

// In spi_core_sva.sv
module spi_core_sva (
    input logic clk, rst_n,
    input logic sclk, mosi, cpol, cpha,
    input logic [3:0] ss_n
    // + Add required internal taps like FSM states
);
    // Assertions related to `spi_core` inside here
endmodule
```

### Requirements Checklist

#### 1. Mandatory Assertions (Section 10.2)
These are strictly required graded assertions. If they overlap with the Verification Plan, the requirement ID is included.

*For `assertions/spi_regfile_sva.sv` (Bound to `u_regfile`)*
- [ ] **`a_apb_psel_2clk`:** `PSEL=1` for at least 2 `PCLK` to complete a transaction.
- [ ] **`a_apb_penable`:** `PENABLE` must only assert while `PSEL=1`.
- [ ] **`a_apb_stable_bus`:** `PADDR`, `PWRITE`, `PWDATA` stable from SETUP to ACCESS of the same transaction.
- [ ] **`a_fifo_no_push_full` (Req R13):** No push when full (after OVF clear) without explicit OVF assertion.
- [ ] **`a_irq_agg` (Req R16):** `IRQ == |(INT_STAT & INT_EN)` every `PCLK` (combinational assertion).

*For `assertions/spi_core_sva.sv` (Bound to `u_core`)*
- [ ] **`a_sclk_idle` (Req R4):** `SCLK` idle level matches `CPOL` whenever not transferring (`BUSY=0`).
- [ ] **`a_mosi_stable` (Req R5):** `MOSI` stable for at least 1 `PCLK` around each sample edge (WIRE-STABILITY).
- [ ] **`a_ss_stable` (Req R20):** `SS_n` held asserted for the entire `WIDTH`-bit transfer.

#### 2. Extra Assertions (Verification Plan)
These are additional specific checks identified in the Verification Plan document to ensure robustness. **Note:** This list is not exhaustive. Read the specification PDF to identify and implement additional assertions that strengthen protocol and design rule coverage.

*For `assertions/spi_regfile_sva.sv` (Bound to `u_regfile`)*
- [ ] **`a_apb_zero_ws` (Req R22):** Check that `PREADY` always equals 1 (zero wait states).
- [ ] **`a_fifo_bounds` (Req R11, R12):** Ensure TX and RX FIFO pointers never exceed depth of 8.
- [ ] **`a_w1c_race` (Req R18):** Verify that a W1C write plus a simultaneous hardware event keeps the bit set.

*For `assertions/spi_core_sva.sv` (Bound to `u_core`)*
- [ ] **`a_xfer_length` (Req R7):** Verify that a transfer takes exactly `WIDTH` SCLK cycles.
