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

### Final Deliverable
The stimulus vocabulary for test writers, the functional coverage model to prove test completeness against the grading rubric, and a successfully compiling top-level testbench.

### Expected API Signature (Hand-off to Phase 2)
The test writers in Phase 2 will instantiate these classes to generate random traffic and record their progress toward the 85% coverage goal:
```systemverilog
// In stim_lib.sv
class spi_txn;
    rand bit [1:0] mode, width;
    rand bit lsb_first, loopback;
    
    // Helper used by tests to pack the 32-bit CTRL register
    function bit [31:0] pack_ctrl();
endclass

// In coverage.sv
class spi_coverage_col;
    // Hooks called by tests at the end of transfers
    function void sample_config(bit [1:0] mode, bit [1:0] width, bit lsb_first, bit loopback);
    function void sample_clkdiv(bit [15:0] div);
    function void sample_fifo(int tx_occ, int rx_occ);
endclass
```

### Requirements Checklist
- [ ] **Randomized Stimulus Classes:** Provide transaction classes for test writers containing constrained-random fields for all valid SPI configurations.
- [ ] **Configuration Coverage:** Provide covergroups that hit all 24 required combinations of Mode × Width × Bit-Ordering.
- [ ] **Corner Case Coverage:** Provide covergroups that explicitly hit the `CLK_DIV` corner values defined in grading Section 10.1 (0, 1, 2, 3, 255, 1024, 65535).
- [ ] **FIFO Coverage:** Provide covergroups that prove the testbench has observed the FIFOs in empty, 1-entry, mid-level, 7-entry, and full states.
- [ ] **Integration:** Instantiate and wire the expanded BFM, Reference Model, and Coverage models into the top-level testbench file.
- [ ] **Test Dispatcher:** Implement the logic in `tb_top.sv` that selects and executes the correct test sequence based on the `+TESTNAME=` simulator argument.
- [ ] **Compilation:** Maintain the Makefile to ensure that all new files compile cleanly without errors.

---

## 🛡️ M7 (SVA & Assertions)
**Target File:** `assertions/spi_sva.sv`

> [!NOTE]
> **Architectural Context: The RTL Split (`apb_regfile` vs `spi_core`)**
> The DUT is structured as a thin top-level module (`spi_master`) that instantiates two clearly bounded sub-blocks (per Section 2 of the spec). This separation of concerns is a crucial digital design pattern:
> - **`apb_regfile` (The Bus Domain):** The "brain" of the system. It isolates the standard AMBA bus protocol from the custom SPI logic. It contains the APB slave logic, all 9 registers, IRQ aggregation, and the TX/RX FIFOs. If this IP were moved to an AXI4-Lite bus, only this file would change.
> - **`spi_core` (The Protocol Domain):** The "muscle" of the system. It knows nothing about APB; it only takes stable commands from the register block. It contains the Shift FSM (IDLE/SHIFT/DELAY), SCLK divider, bit-ordering logic, and loopback mux. This keeps the timing-critical state machine clean and focused solely on the SPI protocol.
> 
> Keep this separation in mind, especially when creating your SystemVerilog Assertions (M7), as properties should be bound to the specific domain they verify.

### Final Deliverable
A comprehensive suite of concurrent SystemVerilog Assertions bound directly to the DUT's internal interfaces to continuously monitor protocol compliance and design rules.

### Expected API Signature (Hand-off to Phase 2 Integration)
M6 (Integration) will need these exact module signatures to exist so they can successfully `bind` them to the DUT in `tb_top.sv`:
```systemverilog
module spi_sva_apb (
    input logic PCLK, PRESETn,
    input logic PSEL, PENABLE, PREADY, PSLVERR,
    input logic [31:0] INT_STAT, INT_EN,
    input logic IRQ
    // (Add any necessary internal FIFO pointers here)
);

module spi_sva_core (
    input logic PCLK, PRESETn,
    input logic SCLK, MOSI, MISO, 
    input logic [3:0] SS_n,
    input logic BUSY, CTRL_EN
);
```

### Requirements Checklist
- [ ] **Binding Strategy:** Apply the assertions correctly across the `u_regfile` and `u_core` module boundaries.
- [ ] **APB Protocol Compliance:** Assert that the APB bus exhibits zero-wait-state behavior (`PREADY` must be 1 during access) and is free of slave errors (`PSLVERR` must be 0).
- [ ] **SPI Polarity Compliance:** Assert that the `SCLK` line rests at the correct `CPOL` level whenever the master is not actively shifting bits.
- [ ] **SPI Timing Compliance:** Assert that the `MOSI` line is stable throughout the entire clock cycle of the sample edge.
- [ ] **SPI Transfer Length:** Assert that a transfer lasts for exactly the programmed `WIDTH` number of SCLK cycles.
- [ ] **Internal Safety Bounds:** Assert that the internal hardware FIFO pointers never drop below 0 or exceed their maximum depth of 8.
- [ ] **IRQ Combinatorial Logic:** Assert that the physical `IRQ` pin always combinatorially matches the aggregated state of the masked interrupts.
- [ ] **W1C Race Condition:** Assert that the hardware correctly preserves a status flag if a W1C clear operation overlaps with a hardware set event.
