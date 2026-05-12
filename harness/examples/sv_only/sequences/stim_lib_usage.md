# stim_lib & Reference Model Integration Guide

This guide shows how to use `spi_sequence_lib`, `spi_txn`, and `spi_ref_model` together in tests to build, execute, predict, and score SPI transfers.

**Locations:**
- Stimulus library: [harness/examples/sv_only/sequences/stim_lib.sv](harness/examples/sv_only/sequences/stim_lib.sv)
- Reference model: [harness/examples/sv_only/env/ref_model.sv](harness/examples/sv_only/env/ref_model.sv)

---

## Overview

### What is the Reference Model?
The `spi_ref_model` class provides:
- **Register tracking** — mirrors APB writes/reads to predict DUT state (CTRL, CLK_DIV, SS_CTRL, INT_EN, INT_STAT, DELAY).
- **Transfer prediction** — predicts TX (MOSI) and RX (MISO) values before transfers complete.
- **Scoreboard checks** — compares predicted vs. observed DUT behavior (register state, SPI data, IRQs, timing).
- **FIFO simulation** — tracks TX/RX FIFO contents and signals (FULL, EMPTY, OVF).

### What is the Stim Library?
The `spi_sequence_lib` class provides:
- **High-level APB tasks** — abstracts repeated register writes (configure_dut, push_single, target_ss, etc.).
- **Transfer choreography** — sequences like `do_transfer` and `do_burst_transfer` bundle multiple tasks.
- **Model mirroring** — automatically calls `ref_model.apb_write(...)` when tasks modify registers.
- **Synchronized reads** — `pop_rx_burst` and `read_status` now use a synchronized APB read helper so both the DUT and `tb_top.u_ref` consume the same register/FIFO state.

### Integration Principle
1. **Before a transfer:** Use `ref_model.predict_transfer(...)` to add expected TX/RX values to predictor queues.
2. **During execution:** Use `spi_sequence_lib` tasks to drive the DUT (which also mirrors writes to the model).
3. **During readout:** Use `spi_sequence_lib::pop_rx_burst(...)` or `spi_sequence_lib::apb_read_sync(...)` so RX_DATA reads pop both the DUT FIFO and the model FIFO.
4. **After a transfer:** Use `ref_model.mark_transfer_done(...)` only when you are modeling transfer completion inside the reference model itself. For real DUT tests, the model should stay aligned by mirrored APB writes and synchronized APB reads, not by manually pushing RX in the predictor path.
5. **Scoreboard checks:** Call `ref_model.check_tx()`, `check_rx()`, `check_status()`, etc. to validate DUT behavior.

---

## Step-by-Step Workflow

### Step 1: Create and Configure a Transaction

```systemverilog
spi_txn txn;
txn = new();

// Randomize the transaction
if (!txn.randomize()) begin
    $display("ERROR: Failed to randomize transaction");
end

// OR manually set fields for deterministic tests
txn.mode      = 2'b00;        // SPI mode 0 (CPOL=0, CPHA=0)
txn.width     = 2'b00;        // 8-bit transfers
txn.clk_div   = 16'd1;        // SCLK = PCLK / 4
txn.loopback  = 1'b0;         // MISO from slave BFM
txn.ss_en     = 4'b0001;      // Assert SS_n[0]
txn.tx_data   = 32'h0000_00AA; // TX payload
```

### Step 2: Configure the DUT (APB writes + model mirror)

```systemverilog
// This writes CLK_DIV, DELAY, INT_EN, CTRL to the DUT
// AND mirrors all writes into tb_top.u_ref automatically
spi_sequence_lib::configure_dut(txn);

// Internally, configure_dut calls:
//   tb_top.u_apb_bfm.apb_write(SL_CLK_DIV, ...);
//   tb_top.u_ref.apb_write(SL_CLK_DIV, ...);  <- Model stays in sync
//   ... and so on for DELAY, INT_EN, CTRL
```

### Step 3: Predict the Transfer (Tell the Model What to Expect)

```systemverilog
bit [31:0] miso_pattern = 32'h0000_0055;  // What the slave will transmit

// Add this transfer to the model's predictor queues
tb_top.u_ref.predict_transfer(
    .tx_data(txn.tx_data),           // Expected TX (MOSI) value
    .miso_pattern(miso_pattern),     // Expected RX (MISO) value
    .loopback(txn.loopback),         // True if loopback mode
    .width(txn.width),               // Transfer width (8/16/32-bit)
    .lsb_first(txn.lsb_first)        // Bit order
);

// This adds masked values to tb_top.u_ref.pred_tx_fifo[] and pred_rx_fifo[]
// The model will check these later using check_tx() and check_rx()
```

### Step 4: Push Data and Assert Slave-Select

```systemverilog
// Push the TX data into the DUT's TX FIFO
// This also mirrors the write to tb_top.u_ref
spi_sequence_lib::push_single(txn);

// Assert the slave-select line(s)
// This also updates tb_top.u_ref.ss_ctrl
spi_sequence_lib::target_ss(txn.ss_en);

// Set the BFM slave mode to match the DUT's configuration
tb_top.bfm_mode = txn.mode;
tb_top.bfm_pattern = miso_pattern;  // Slave will transmit this
```

### Step 5: Wait for the Transfer to Complete

```systemverilog
// Poll the DUT's STATUS.BUSY until it clears
spi_sequence_lib::wait_idle();

// At this point:
//   - The DUT has shifted all 8/16/32 bits
//   - MOSI data has been observed on the SPI interface
//   - MISO data has been captured into the DUT's RX FIFO
//   - RX_FULL or TRANSFER_DONE interrupt may have fired
```

### Step 6: Update the Model (Mark Transfer Complete)

```systemverilog
bit [31:0] observed_rx;

// Read the DUT RX_DATA register through the synchronized helper.
// This pops the DUT RX FIFO and also pops the model RX FIFO, so the two
// states stay aligned.
spi_sequence_lib::apb_read_sync(SL_RX_DATA, observed_rx);
```

For real DUT tests, that synchronized read is usually the right state update.
`mark_transfer_done(...)` is still useful when you want to advance the model's
internal transfer bookkeeping directly, but it is not the same thing as draining
the observed RX FIFO from hardware.

### Step 7: Deassert Slave-Select and Read RX Data

```systemverilog
// Deassert SS_n after the transfer completes
spi_sequence_lib::target_ss(4'b0000);

// Read the RX data through the synchronized helper
bit [31:0] dut_rx_data;
spi_sequence_lib::apb_read_sync(SL_RX_DATA, dut_rx_data);

// The model's RX FIFO was popped too, so the real HW and SW state match
```

### Step 8: Scoreboard Checks

```systemverilog
// Retrieve current model state
bit [31:0] model_status  = tb_top.u_ref.get_status();
bit [31:0] model_int_stat = tb_top.u_ref.int_stat;

// Perform scoreboard checks
// These compare OBSERVED vs. PREDICTED and increment error_count if they mismatch

// Check TX (MOSI) against prediction
tb_top.u_ref.check_tx(observed_mosi_value);

// Check RX (MISO) against prediction
tb_top.u_ref.check_rx(dut_rx_data);

// Check STATUS register
bit [31:0] dut_status;
tb_top.u_apb_bfm.apb_read(SL_STATUS, dut_status);
tb_top.u_ref.check_status(dut_status);

// Check INT_STAT register
bit [31:0] dut_int_stat;
tb_top.u_apb_bfm.apb_read(SL_INT_STAT, dut_int_stat);
tb_top.u_ref.check_int_stat(dut_int_stat);

// Check INT_EN and derive predicted IRQ
bit predicted_irq = tb_top.u_ref.predict_irq();

// Check SS_n combinational output
bit [3:0] dut_ss_n;
// (read from SVA or monitor)
tb_top.u_ref.check_ss_n(dut_ss_n);

// Check transfer took the correct number of SCLK cycles
// (observed_sclk_cycles would come from a monitor or assertion)
tb_top.u_ref.check_transfer_length(observed_sclk_cycles);
```

### Step 9: Handle Interrupt W1C (Write-One-to-Clear)

```systemverilog
// Read INT_STAT before clearing
bit [31:0] int_stat_before;
spi_sequence_lib::clear_interrupts(int_stat_before);

// This task:
//   1. Reads INT_STAT into int_stat_before
//   2. Writes it back (W1C mechanism clears set bits)
//   3. Mirrors the write to tb_top.u_ref, which applies the same W1C logic

// Verify the clear worked
bit [31:0] cleared_stat;
tb_top.u_apb_bfm.apb_read(SL_INT_STAT, cleared_stat);
tb_top.u_ref.check_int_stat(cleared_stat);
```

---

## Complete Minimal Test Example

```systemverilog
module my_simple_test;
    import tb_pkg::*;

    initial begin
        spi_txn txn;
        bit [31:0] rx_word;
        bit [31:0] status;

        // Setup
        wait(tb_top.reset_done);

        // Create and configure transaction
        txn = new();
        if (!txn.randomize()) $fatal(1, "Randomize failed");

        // Step 2: Configure DUT (also mirrors to model)
        spi_sequence_lib::configure_dut(txn);

        // Step 3: Predict the transfer
        tb_top.u_ref.predict_transfer(
            .tx_data(txn.tx_data),
            .miso_pattern(32'h0055),
            .loopback(txn.loopback),
            .width(txn.width),
            .lsb_first(txn.lsb_first)
        );

        // Step 4: Push data and assert SS
        spi_sequence_lib::push_single(txn);
        spi_sequence_lib::target_ss(txn.ss_en);
        tb_top.bfm_mode    = txn.mode;
        tb_top.bfm_pattern = 32'h0055;

        // Step 5: Wait for idle
        spi_sequence_lib::wait_idle();

        // Step 6: Mark transfer done (model updates)
        tb_top.u_ref.mark_transfer_done(32'h0055);

        // Step 7: Deassert SS and read RX
        spi_sequence_lib::target_ss(4'b0000);
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);

        // Step 8: Scoreboard checks
        tb_top.u_ref.check_rx(rx_word);
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        tb_top.u_ref.check_status(status);

        // Print result
        if (tb_top.u_ref.error_count == 0) begin
            $display("[TEST_PASSED]");
        end else begin
            $display("[TEST_FAILED] Errors: %0d", tb_top.u_ref.error_count);
        end
        $finish;
    end
endmodule
```

---

## Burst Transfer Example

```systemverilog
spi_txn_fifo burst_txn[$];
bit [31:0] rx_q[$];

// Create 4 transactions for a burst
for (int i = 0; i < 4; i++) begin
    spi_txn txn = new();
    if (!txn.randomize()) $fatal(1, "Randomize failed");
    burst_txn.push_back(txn);
end

// Configure once (all transfers use the same config)
spi_sequence_lib::configure_dut(burst_txn[0]);

// Predict all transfers in advance
foreach (burst_txn[i]) begin
    tb_top.u_ref.predict_transfer(
        .tx_data(burst_txn[i].tx_data),
        .miso_pattern(32'h0055 + i),   // Different pattern per transfer
        .loopback(burst_txn[i].loopback),
        .width(burst_txn[i].width),
        .lsb_first(burst_txn[i].lsb_first)
    );
end

// High-level helper: does push_burst, wait_idle, pop_rx_burst
spi_sequence_lib::do_burst_transfer(burst_txn, rx_q);

// Check each RX against prediction
foreach (rx_q[i]) begin
    tb_top.u_ref.check_rx(rx_q[i]);
end
```

---

## Key Reference Model Functions

### Prediction
- `predict_transfer(tx_data, miso_pattern, loopback, width, lsb_first)` — queue TX/RX expectations.
- `predict_single_byte(tx_byte, miso_pattern, loopback)` — convenience for 8-bit MSB-first transfers.

### Transfer Completion
- `mark_transfer_done(rx_miso_val)` — pop TX, push RX, update status/IRQ.
- `spi_transfer_complete(rx_miso_val)` — internal call; same effect as `mark_transfer_done`.

### Synchronized Readout
- `spi_sequence_lib::apb_read_sync(addr, data)` — read from hardware and the reference model in the same call.
- `spi_sequence_lib::pop_rx_burst(rx_q)` — drains RX_DATA from both hardware and the reference model.
- `spi_sequence_lib::read_status(status)` — returns STATUS using the synchronized read path.

### Scoreboard Checks
- `check_tx(observed)` — validate MOSI against prediction.
- `check_rx(observed)` — validate MISO against prediction.
- `check_status(observed)` — validate STATUS register state.
- `check_int_stat(observed)` — validate INT_STAT register state.
- `check_irq(observed)` — validate IRQ output.
- `check_sclk_period(measured_cycles)` — validate SCLK timing.
- `check_ss_n(observed)` — validate SS_n output.
- `check_transfer_length(measured_cycles)` — validate transfer bit-count.

### State Queries
- `get_status()` — compute dynamic STATUS register from FIFO sizes and flags.
- `predict_irq()` — compute expected IRQ = |(INT_STAT & INT_EN).
- `predict_sclk_period()` — formula: 2 * (DIV + 1) PCLK cycles.
- `predict_delay_pclk_cycles()` — formula: DELAY[7:0] * SCLK_half_period.

---

## Suggested Test Development Workflow

1. **Sanity test** — Single transfer using `do_transfer()` high-level helper.
2. **Mode coverage test** — Randomize width/CPOL/CPHA; predict and check each.
3. **Burst test** — Multiple transfers; predict all up front, then verify RX queue.
4. **Interrupt test** — Set INT_EN, read INT_STAT, clear via W1C, check state.
5. **FIFO stress test** — Fill TX FIFO, trigger TX_FULL, then RX_FULL; check OVF flags.

---

## Common Pitfalls

- **Forgetting to predict:** Call `predict_transfer()` BEFORE each transfer, or scoreboard checks will fail with "no prediction" errors.
- **Wrong MISO pattern:** Set `tb_top.bfm_pattern` to match what you predicted, or RX data will not match.
- **Not using synchronized reads:** If you read RX_DATA directly from hardware without also popping the model, the DUT and model FIFOs will diverge.
- **Mixing wrapper and explicit ref calls:** Use one approach consistently in a test to avoid confusion.
- **INT_STAT W1C races:** Use `clear_interrupts()` (which reads then writes) to avoid missing events.
