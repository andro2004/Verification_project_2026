// =============================================================================
// width_coverage_test.sv  (Owner: M6)
// -----------------------------------------------------------------------------
// Exercises edge-case data patterns at 8-bit, 16-bit, and 32-bit transfer
// widths (R6, R7). For each width the test:
//   1. Configures the DUT + slave BFM for the chosen width (mode 0, MSB-first).
//   2. Pushes a known TX word whose upper bits exercise the boundary mask.
//   3. Runs the transfer, reads RX_DATA, and checks against the golden
//      ref_model prediction.
//   4. Samples cg_config coverage so the cp_width / cx_mode_width bins fill.
//
// Sub-tests per width:
//   a. "all-ones" pattern   — verifies all data bits are shifted correctly.
//   b. "all-zeros" pattern  — trivial correctness baseline.
//   c. "alternating" pattern — walking 0xAA / 0x55 to catch stuck-bit bugs.
//   d. "boundary" pattern   — MSB set, rest zero (e.g. 0x80 for 8-bit).
//   e. LSB-first variant    — same boundary pattern with lsb_first=1.
//
// Uses stim_lib helpers and the golden ref_model for scoreboard checks.
// =============================================================================

`ifndef WIDTH_COVERAGE_TEST_SV
`define WIDTH_COVERAGE_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class width_coverage_test;

    // =========================================================================
    // Helper: run a single transfer, check RX against ref_model, sample cov.
    // =========================================================================
    static task do_width_xfer(
        input  string           label,
        input  bit [1:0]        mode,
        input  bit [1:0]        width,
        input  bit              lsb_first,
        input  bit [31:0]       tx_data,
        input  bit [31:0]       miso_pattern,
        ref    spi_ref_model    ref_model,
        ref    spi_coverage_col coverage
    );
        spi_txn   txn;
        bit [31:0] rx_word;

        // --- reset DUT between sub-tests so FIFOs are clean -----------------
        spi_sequence_lib::reset_dut();
        ref_model.reset();

        // --- build transaction ----------------------------------------------
        txn = new();
        txn.mode       = mode;
        txn.width      = width;
        txn.lsb_first  = lsb_first;
        txn.loopback   = 1'b0;       // external MISO path — use slave BFM
        txn.clk_div    = 16'd4;      // fast clock for simulation
        txn.delay_cfg  = 8'd0;
        txn.ss_en      = 4'b0001;    // assert SS lane 0
        txn.tx_data    = tx_data;

        // --- configure slave BFM to match -----------------------------------
        tb_top.bfm_mode      = mode;
        tb_top.bfm_pattern   = miso_pattern;
        tb_top.bfm_lsb_first = lsb_first;
        tb_top.bfm_width     = width;

        // --- configure DUT via APB ------------------------------------------
        spi_sequence_lib::configure_dut(txn);

        // --- predict the expected RX ----------------------------------------
        ref_model.predict_transfer(
            .tx_data      (tx_data),
            .miso_pattern (miso_pattern),
            .loopback     (1'b0),
            .width        (width),
            .lsb_first    (lsb_first)
        );

        // --- mark transfer start in ref model --------------------------------
        ref_model.mark_transfer_start();

        // --- push TX, assert SS, wait, deassert SS --------------------------
        spi_sequence_lib::push_single(txn);
        spi_sequence_lib::target_ss(txn.ss_en);
        spi_sequence_lib::wait_idle();
        spi_sequence_lib::target_ss(4'b0000);

        // --- mark transfer done in ref model ---------------------------------
        ref_model.mark_transfer_done(miso_pattern);

        // --- read RX_DATA and check -----------------------------------------
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);
        ref_model.check_rx(rx_word);

        // --- sample coverage ------------------------------------------------
        coverage.sample_config(
            .mode     (mode),
            .width    (width),
            .lsb_first(lsb_first),
            .loopback (1'b0)
        );

        $display("[INFO] width_coverage_test: %s  TX=0x%08h  RX=0x%08h  (width=%0d, lsb=%0b)",
                 label, tx_data, rx_word,
                 (width == 2'b00) ? 8 : (width == 2'b01) ? 16 : 32,
                 lsb_first);
    endtask

    // =========================================================================
    // Main entry point — called from tb_top dispatcher
    // =========================================================================
    static task run(ref spi_ref_model    ref_model,
                    ref spi_coverage_col coverage);

        $display("[INFO] width_coverage_test: starting");

        // =====================================================================
        // 8-BIT WIDTH (ctrl[7:6] = 2'b00)
        // =====================================================================
        $display("[INFO] width_coverage_test: --- 8-bit transfers ---");

        // (a) all-ones
        do_width_xfer("8b_all_ones",   2'b00, 2'b00, 1'b0,
                      32'h0000_00FF, 32'h0000_00FF, ref_model, coverage);
        // (b) all-zeros
        do_width_xfer("8b_all_zeros",  2'b00, 2'b00, 1'b0,
                      32'h0000_0000, 32'h0000_0000, ref_model, coverage);
        // (c) alternating 0xAA
        do_width_xfer("8b_alt_AA",     2'b00, 2'b00, 1'b0,
                      32'h0000_00AA, 32'h0000_0055, ref_model, coverage);
        // (d) boundary — MSB only
        do_width_xfer("8b_boundary",   2'b00, 2'b00, 1'b0,
                      32'h0000_0080, 32'h0000_0080, ref_model, coverage);
        // (e) LSB-first variant
        do_width_xfer("8b_lsb_first",  2'b00, 2'b00, 1'b1,
                      32'h0000_0080, 32'h0000_0080, ref_model, coverage);

        // =====================================================================
        // 16-BIT WIDTH (ctrl[7:6] = 2'b01)
        // =====================================================================
        $display("[INFO] width_coverage_test: --- 16-bit transfers ---");

        // (a) all-ones
        do_width_xfer("16b_all_ones",  2'b00, 2'b01, 1'b0,
                      32'h0000_FFFF, 32'h0000_FFFF, ref_model, coverage);
        // (b) all-zeros
        do_width_xfer("16b_all_zeros", 2'b00, 2'b01, 1'b0,
                      32'h0000_0000, 32'h0000_0000, ref_model, coverage);
        // (c) alternating 0xAAAA
        do_width_xfer("16b_alt_AAAA",  2'b00, 2'b01, 1'b0,
                      32'h0000_AAAA, 32'h0000_5555, ref_model, coverage);
        // (d) boundary — MSB only (bit 15)
        do_width_xfer("16b_boundary",  2'b00, 2'b01, 1'b0,
                      32'h0000_8000, 32'h0000_8000, ref_model, coverage);
        // (e) LSB-first variant
        do_width_xfer("16b_lsb_first", 2'b00, 2'b01, 1'b1,
                      32'h0000_8000, 32'h0000_8000, ref_model, coverage);

        // =====================================================================
        // 32-BIT WIDTH (ctrl[7:6] = 2'b10)
        // =====================================================================
        $display("[INFO] width_coverage_test: --- 32-bit transfers ---");

        // (a) all-ones
        do_width_xfer("32b_all_ones",  2'b00, 2'b10, 1'b0,
                      32'hFFFF_FFFF, 32'hFFFF_FFFF, ref_model, coverage);
        // (b) all-zeros
        do_width_xfer("32b_all_zeros", 2'b00, 2'b10, 1'b0,
                      32'h0000_0000, 32'h0000_0000, ref_model, coverage);
        // (c) alternating 0xAAAAAAAA
        do_width_xfer("32b_alt_AAAA",  2'b00, 2'b10, 1'b0,
                      32'hAAAA_AAAA, 32'h5555_5555, ref_model, coverage);
        // (d) boundary — MSB only (bit 31)
        do_width_xfer("32b_boundary",  2'b00, 2'b10, 1'b0,
                      32'h8000_0000, 32'h8000_0000, ref_model, coverage);
        // (e) LSB-first variant
        do_width_xfer("32b_lsb_first", 2'b00, 2'b10, 1'b1,
                      32'h8000_0000, 32'h8000_0000, ref_model, coverage);

        // =====================================================================
        // CROSS-MODE × WIDTH: Hit remaining modes (1, 2, 3) for each width
        // to fill the cx_mode_width cross bins in cg_config.
        // =====================================================================
        $display("[INFO] width_coverage_test: --- cross mode × width ---");

        // Mode 1 (CPOL=0, CPHA=1) × each width
        do_width_xfer("mode1_w8",  2'b01, 2'b00, 1'b0,
                      32'h0000_005A, 32'h0000_00A5, ref_model, coverage);
        do_width_xfer("mode1_w16", 2'b01, 2'b01, 1'b0,
                      32'h0000_5A5A, 32'h0000_A5A5, ref_model, coverage);
        do_width_xfer("mode1_w32", 2'b01, 2'b10, 1'b0,
                      32'h5A5A_5A5A, 32'hA5A5_A5A5, ref_model, coverage);

        // Mode 2 (CPOL=1, CPHA=0) × each width
        do_width_xfer("mode2_w8",  2'b10, 2'b00, 1'b0,
                      32'h0000_005A, 32'h0000_00A5, ref_model, coverage);
        do_width_xfer("mode2_w16", 2'b10, 2'b01, 1'b0,
                      32'h0000_5A5A, 32'h0000_A5A5, ref_model, coverage);
        do_width_xfer("mode2_w32", 2'b10, 2'b10, 1'b0,
                      32'h5A5A_5A5A, 32'hA5A5_A5A5, ref_model, coverage);

        // Mode 3 (CPOL=1, CPHA=1) × each width
        do_width_xfer("mode3_w8",  2'b11, 2'b00, 1'b0,
                      32'h0000_005A, 32'h0000_00A5, ref_model, coverage);
        do_width_xfer("mode3_w16", 2'b11, 2'b01, 1'b0,
                      32'h0000_5A5A, 32'h0000_A5A5, ref_model, coverage);
        do_width_xfer("mode3_w32", 2'b11, 2'b10, 1'b0,
                      32'h5A5A_5A5A, 32'hA5A5_A5A5, ref_model, coverage);

        // =====================================================================
        // CONSTRAINED RANDOM TRANSACTIONS
        // =====================================================================
        $display("[INFO] width_coverage_test: --- 20 Constrained Random Transfers ---");
        for (int i = 0; i < 20; i++) begin
            spi_txn rand_txn = new();
            if (!rand_txn.randomize()) $fatal(1, "Failed to randomize txn");
            
            do_width_xfer(
                $sformatf("rand_%0d", i), 
                rand_txn.mode, 
                rand_txn.width, 
                rand_txn.lsb_first, 
                rand_txn.tx_data, 
                $urandom(), 
                ref_model, 
                coverage
            );
        end

        $display("[INFO] width_coverage_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask

endclass

`endif // WIDTH_COVERAGE_TEST_SV
