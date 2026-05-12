<div align="center">
  
# 🎯 Mastering the `spi_ref_model` in Test Scenarios
*A Comprehensive Guide to Synchronization, Scoreboarding, and Bug Trapping*

</div>

---

The **`spi_ref_model`** is the "Golden Truth" of your verification environment. It is an **un-timed, behavioral model** of the SPI Master Controller. While your RTL (the DUT) operates on clock edges and nanosecond delays, the reference model operates entirely on **events and transactions**. 

To accurately trap bugs in the DUT, your test files must act as the "bridge" between the timed DUT and the un-timed reference model, keeping them perfectly synchronized.

> [!IMPORTANT]
> **The Golden Rule:** Every action that affects the state of the DUT must be explicitly communicated to the reference model. If they fall out of sync, your scoreboard will generate false positives (reporting bugs that don't exist) or false negatives (missing actual bugs).

---

## 🧹 1. Resetting the Model

Whenever a new test or sub-test begins, you must flush the pipelines.

> [!CAUTION]
> If you reset the DUT but forget to reset the reference model, the model will retain "ghost" data in its FIFOs and stale interrupt flags. Your very next check will instantly fail!

**Always reset both side-by-side:**
```systemverilog
// 1. Send hard reset signals to the DUT hardware
spi_sequence_lib::reset_dut();

// 2. Flush the reference model's FIFOs and zero out all registers
ref_model.reset();
```

---

## 📝 2. Register Configuration (Shadowing)

The reference model must always know the current state of the DUT's control registers (like `CLK_DIV`, `CTRL`, and `INT_EN`) so it can accurately predict behavior.

### 🌟 Best Practice: Use `stim_lib`
Whenever possible, use the sequence library. It automatically generates the APB writes to the DUT and keeps the configuration clean.
```systemverilog
spi_sequence_lib::configure_dut(txn); // Configures the DUT hardware safely
```

### ⚠️ Manual Shadowing
If you are doing advanced stress-testing and writing directly to the APB bus, **you must shadow that write to the reference model.**

> [!NOTE]
> Why? Because `ref_model.apb_write()` isn't just storing a value—it runs internal logic! For example, writing to `INT_STAT` in the reference model triggers the Write-1-to-Clear (W1C) logic to clear internal flags.

```systemverilog
// ❌ WRONG: Ref model will drift out of sync!
tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0004); 

// ✅ CORRECT: Both units receive the data at the exact same time
tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0004); 
ref_model.apb_write(8'h10, 32'h0000_0004);       
```

---

## 🔄 3. The Transfer Lifecycle (The Heart of Verification)

Because the reference model doesn't have a clock (`clk`), it relies on you to tell it when a physical transfer starts and ends on the wires.

### 🔮 Step A: Predict the Future
Before you start driving the DUT, you must load the model's `pred_rx_fifo` with the expected golden outcome of the transfer.
```systemverilog
ref_model.predict_transfer(
    .tx_data(txn.tx_data),             // What we are sending
    .miso_pattern(tb_top.bfm_pattern), // What the BFM will reply with
    .loopback(txn.loopback),           // Loopback mode toggle
    .width(txn.width),                 // 8, 16, or 32 bits
    .lsb_first(txn.lsb_first)          // Shift direction
);
```

### 🚀 Step B: Mark the Start
Right before (or right after) you assert the Slave Select (`SS_CTRL`) lane, tell the model the transfer has begun.
> [!TIP]
> This is used by the model to freeze the current configuration (like `CLK_DIV` and `MODE`) to test Requirement **R25** (parameters are held for the duration of a transfer).
```systemverilog
ref_model.mark_transfer_start();

// Now actually drive the hardware...
spi_sequence_lib::push_single(txn);
spi_sequence_lib::target_ss(txn.ss_en);
```

### 🏁 Step C: Mark the End
Once the hardware indicates it is done (e.g., `wait_idle()` finishes, or `TRANSFER_DONE` fires), you **must** notify the reference model.
> [!IMPORTANT]
> **This is the most critical function in the model.** Calling `mark_transfer_done` tells the model to pop data from its `tx_fifo`, push the expected data to its `rx_fifo`, and update its internal `INT_STAT` (like calculating `TX_EMPTY` or `RX_FULL`).
```systemverilog
// The DUT is idle. Evaluate the transfer outcome!
ref_model.mark_transfer_done(tb_top.bfm_pattern);
```

---

## 📥 4. Reading Data (Popping FIFOs)

If you read the `RX_DATA` register (Address `0x0C`) from the DUT, the DUT physically pops an item out of its RX FIFO. **You must do the same to the reference model!**

> [!WARNING]
> If you forget to pop the reference model's FIFO, its internal size will grow forever. Later in your test, when you check `STATUS`, the reference model will scream `[SCOREBOARD_ERROR]` because it thinks the RX FIFO is full while the DUT knows it is empty!

**Always use the `apb_read_sync` helper:**
```systemverilog
// ✅ This task safely reads the DUT *and* calls ref_model.apb_read() for you!
spi_sequence_lib::apb_read_sync(8'h0C, rx_word); 
```

---

## 🕵️‍♂️ 5. Scoreboarding (Checking for Bugs)

Once the lifecycles are synced, you use the `check_*` tasks to compare the DUT against the golden model. If the DUT violates the spec, these functions will print a `[SCOREBOARD_ERROR]` and increment the `error_count`.

| Checker Task | What It Verifies | When to Call It |
| :--- | :--- | :--- |
| `check_rx(rx_word)` | Verifies the data read from APB exactly matches the `pred_rx_fifo` | Immediately after reading `RX_DATA` |
| `check_status(val)` | Checks `TX_FULL`, `TX_EMPTY`, `RX_FULL`, `RX_EMPTY`, `BUSY` | While pushing/popping FIFOs or during idle |
| `check_int_stat(val)` | Checks sticky flags: `TX_OVF`, `RX_OVF`, `XFER_DONE` | After an event occurs (like filling a FIFO) |
| `check_irq(pin)` | Checks the global `IRQ` line logic against `INT_EN` masks | During masking or interrupt tests |
| `check_sclk_period(n)`| Validates the formula `SCLK = PCLK / (2*(DIV+1))` | During clock divider corner tests |

---

## 🎨 Putting It All Together: The Perfect Loop

Here is the "Gold Standard" template for safely executing a transfer and verifying its results without desyncing the model:

```systemverilog
// 1. Tell the model what will happen
ref_model.predict_transfer(32'hAA, 32'h55, 0, 2'b00, 0);

// 2. Lock the configuration and start
ref_model.mark_transfer_start();
spi_sequence_lib::push_single(txn);
spi_sequence_lib::target_ss(4'b0001);

// 3. Wait for the DUT hardware to physically finish shifting
spi_sequence_lib::wait_idle();
spi_sequence_lib::target_ss(4'b0000);

// 4. Update the model's internal FIFOs and Event Flags
ref_model.mark_transfer_done(32'h55);

// 5. Read the DUT, Synchronize the Model, and Check for Bugs!
spi_sequence_lib::apb_read_sync(8'h0C, rx_word);
ref_model.check_rx(rx_word);
```
