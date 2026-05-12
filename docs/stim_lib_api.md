# stim_lib API Reference

This file is a short API reference for the stimulus library in [harness/examples/sv_only/sequences/stim_lib.sv](../harness/examples/sv_only/sequences/stim_lib.sv).

## Transaction classes

- `spi_txn` — base randomizable transaction descriptor.
- `spi_txn_clkdiv_corner` — forces clock-divider corner values.
- `spi_txn_fifo` — forces FIFO-friendly burst behavior.
- `spi_txn_delay` — forces delay corner values.

## Sequence library tasks

- `configure_dut(spi_txn txn)` — configure DUT registers and mirror the writes into `tb_top.u_ref`.
- `configure_dut(spi_txn txn, ref spi_ref_model ref_model)` — explicit-model variant.
- `push_single(spi_txn txn)` — write one TX word and mirror to the model.
- `push_single(spi_txn txn, ref spi_ref_model ref_model)` — explicit-model variant.
- `push_burst(spi_txn txn_q[$])` — write a burst of TX words and mirror to the model.
- `push_burst(spi_txn txn_q[$], ref spi_ref_model ref_model)` — explicit-model variant.
- `target_ss(bit [3:0] ss_en_bits)` — drive SS control and mirror to the model.
- `wait_idle()` — poll STATUS.BUSY until the DUT is idle.
- `read_status(output bit [31:0] status)` — synchronized STATUS read.
- `clear_interrupts(output bit [31:0] int_stat_before)` — read INT_STAT, clear it, and mirror the W1C action.
- `inject_error(...)` — APB error-path helper.
- `do_transfer(spi_txn txn, output bit [31:0] rx_word)` — single-transfer helper.
- `do_burst_transfer(spi_txn txn_q[$], output bit [31:0] rx_q[$])` — burst-transfer helper.
- `reset_dut()` — clear control and interrupt state.
- `apb_read_sync(input bit [7:0] addr, output bit [31:0] data)` — read from hardware and the reference model together.

## Typical use

```systemverilog
spi_txn txn = new();
bit [31:0] rx_word;

if (!txn.randomize()) $fatal(1, "randomize failed");

spi_sequence_lib::configure_dut(txn);
tb_top.u_ref.predict_transfer(txn.tx_data, tb_top.bfm_pattern, txn.loopback, txn.width, txn.lsb_first);
spi_sequence_lib::push_single(txn);
spi_sequence_lib::target_ss(txn.ss_en);
spi_sequence_lib::wait_idle();
spi_sequence_lib::apb_read_sync(SL_RX_DATA, rx_word);
tb_top.u_ref.check_rx(rx_word);
```
