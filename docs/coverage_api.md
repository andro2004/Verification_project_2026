# Functional Coverage API Documentation (`coverage.sv`)

This document details the functional coverage model available in `coverage.sv`. DV engineers can use this API to sample and collect coverage metrics across various SPI controller features during test execution.

## File Information
- **File:** `coverage.sv`
- **Location:** `harness/examples/sv_only/env/`
- **Class:** `spi_coverage_col`

## Class Instantiation
Initialize the coverage collector in your testbench environment or base test:

```systemverilog
spi_coverage_col cov;
cov = new();
```

## Available Covergroups

The `spi_coverage_col` class instantiates several covergroups to track different elements of the SPI Master Controller protocol.

*   `cg_config`: Covers SPI modes (CPOL/CPHA combination), transfer width sizes, data order (LSB/MSB first), and loopback settings.
*   `cg_clkdiv`: Tracks explicitly interesting clock divider values (0, 1, 2, 3, 255, 1024, 65535) and other random values.
*   `cg_fifo`: Samples the occupancy of the TX and RX FIFOs (empty, 1 item, mid-level, near full, and full).
*   `cg_delay`: Tracks inter-transfer delay times (e.g., 0, 1, and large delays >= 128).
*   `cg_interrupt`: Triggers on INT_STAT flags, INT_EN mask bit settings, and their cross combinations.
*   `cg_ss`: Ensures all single Slave Select (`SS_n`) lanes, combinations, or none are asserted appropriately.
*   `cg_register`: Records read and write transactions directed at all mapped addresses as well as the reserved aperture space.

## Sampling API / Methods

The class provides several sampling functions corresponding to each covergroup. You should call these methods at the appropriate times from your TB, sequence, or scoreboard to fulfill the minimum 85% coverage gate.

### `sample_config`
Samples SPI configuration settings (Mode, LSB first preference, Width, and Loopback enable).
**Signature:**
```systemverilog
function void sample_config(
    input bit [1:0] mode, 
    input bit       lsb_first, 
    input bit [1:0] width, 
    input bit       loopback
);
```
**Usage:** Call when the CTRL register is updated or just before initiating an SPI transfer.

### `sample_clkdiv`
Samples integer timing scaler values.
**Signature:**
```systemverilog
function void sample_clkdiv(
    input bit [15:0] div
);
```
**Usage:** Call after modifying the CLK_DIV register.

### `sample_fifo`
Records the occupancy of the hardware FIFOs.
**Signature:**
```systemverilog
function void sample_fifo(
    input int tx_occ, 
    input int rx_occ
);
```
**Usage:** Call periodically when data is queued or read (e.g., in a monitor or immediately following an APB interaction affecting FIFOs).

### `sample_delay`
Samples delay parameters loaded into the SPI controller.
**Signature:**
```systemverilog
function void sample_delay(
    input bit [7:0] delay
);
```
**Usage:** Call upon initialization or updates to the DELAY register.

### `sample_interrupt`
Records interrupt status flags alongside the current mask to catch interrupts fired when masked/unmasked.
**Signature:**
```systemverilog
function void sample_interrupt(
    input bit [4:0] int_stat, 
    input bit [4:0] int_en
);
```
**Usage:** Call during interrupt service routines or anywhere `int_stat` is being pooled or validated.

### `sample_ss`
Records which slave select lane(s) are active.
**Signature:**
```systemverilog
function void sample_ss(
    input bit [3:0] ss_n
);
```
**Usage:** Call whenever the `ss_ctrl` register receives a configuration write.

### `sample_register`
Samples APB bus bus-level activity across memory-mapped endpoints.
**Signature:**
```systemverilog
function void sample_register(
    input bit [7:0] addr, 
    input bit       is_write
);
```
**Usage:** Extract the address and read/write bits linearly from the APB monitor each transfer.