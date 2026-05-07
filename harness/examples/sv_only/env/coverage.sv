// =============================================================================
// coverage.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal functional-coverage collector built on covergroups. Students must
// extend this to hit the 85% functional-coverage gate in the grading rubric.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    bit [1:0] cv_mode;
    bit       cv_lsb_first;
    bit [1:0] cv_width;

    covergroup cg_config;
        option.per_instance = 1;
        cp_mode : coverpoint cv_mode  {
            bins modes[] = {[0:3]};
        }
        cp_first : coverpoint cv_lsb_first {
            bins msb_first = {0};
            bins lsb_first = {1};
        }
        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        }
        cx_mode_width : cross cp_mode, cp_width;
    endgroup

    function new();
        cg_config = new();
        // TODO: Initialize all additional covergroups below in new()
    endfunction

    // =========================================================================
    // Covergroup Skeletons - Implementation Required
    // =========================================================================

    covergroup cg_clkdiv;
        // TODO: Create explicit bins for DIV values: 0, 1, 2, 3, 255, 1024, 65535.
        // Also add a random covering bin over the full range [0:65535].
    endgroup

    covergroup cg_fifo;
        // TODO: Create occupancy bins for both TX and RX.
        // Each FIFO should have bins for: empty (0), 1, mid (4), 7, and full (8).
        // Total of 10 bins across the two FIFOs.
    endgroup

    covergroup cg_delay;
        // TODO: Create bins for inter-transfer delay values: 0, 1, and one large value (>= 128).
    endgroup

    covergroup cg_interrupt;
        // TODO: Create 32 combination bins for the 5 interrupt sources.
        // For each interrupt source, cover: asserted, cleared (W1C), and asserted-while-masked (INT_EN=0).
    endgroup

    covergroup cg_ss;
        // TODO: Create bins to cover all slave select patterns.
        // Include: each individual SS_n lane asserted alone, and multi-slave scenarios.
    endgroup

    covergroup cg_register;
        // TODO: Create bins for all 9 registers (0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20).
        // Also cover reserved offsets (0x24+). For each register, track read vs. write operations.
    endgroup

    function void sample_config(bit [1:0] mode, bit [1:0] width, bit lsb_first, bit loopback);
        // TODO: Update cg_config to cross all 4 modes × 3 widths × 2 orderings → 24 bins
        // Also cross in loopback (on/off) for additional coverage.
        cv_mode      = mode;
        cv_lsb_first = lsb_first;
        cv_width     = width;
        cg_config.sample();
    endfunction

    function void sample_clkdiv(bit [15:0] div);
        // TODO: Sample cg_clkdiv with the DIV value
    endfunction

    function void sample_fifo(int tx_occ, int rx_occ);
        // TODO: Sample cg_fifo with TX and RX occupancy values
    endfunction

    function void sample_delay(bit [7:0] delay);
        // TODO: Sample cg_delay with the delay value
    endfunction

    function void sample_interrupt(bit [4:0] int_stat, bit [4:0] int_en);
        // TODO: Sample cg_interrupt with INT_STAT and INT_EN values
    endfunction

    function void sample_ss(bit [3:0] ss_pattern);
        // TODO: Sample cg_ss with the SS pattern
    endfunction

    function void sample_register(bit [7:0] addr, bit is_write);
        // TODO: Sample cg_register with register address and read/write flag
    endfunction

endclass

`endif // SPI_COVERAGE_COL_SV
