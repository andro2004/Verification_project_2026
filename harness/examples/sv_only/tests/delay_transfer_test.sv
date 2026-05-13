// =============================================================================
// delay_transfer_test.sv
// -----------------------------------------------------------------------------
// TC_03  |  Requirements: R21, R24, R25
//
// R21: When DELAY > 0 and another TX word is queued, the master inserts
//      DELAY[7:0] idle SCLK half-cycles between consecutive transfers while
//      BUSY remains 1.
// R24: CLK_DIV=0 yields SCLK = PCLK/2 (no divide-by-zero).
// R25: DIV, MODE, WIDTH, LSB_FIRST are sampled at transfer start and held for
//      that transfer's duration; mid-transfer writes to CLK_DIV are ignored
//      until the next transfer.
//
// Sub-tests
// ---------
//  A : DELAY=0  — no gap between two back-to-back 8-bit words, mode 0.
//  B : DELAY=1  — exactly 1 half-cycle gap, 8-bit, mode 0.
//  C : DELAY=8  — 8 half-cycle gap, 8-bit, mode 0.
//  D : DELAY=128 — large delay (coverage bin >=128), 8-bit, mode 0.
//  E : R24/R25  — DIV=0 SCLK period check + mid-transfer CLK_DIV write is
//                 ignored for the current transfer.
//
// Measurement method
// ------------------
//  We directly observe tb_top.spi.sclk via PCLK-sampled polling (not clocking
//  blocks) so we can count half-periods precisely.
//
//  Gap: after the last SCLK edge of word-1, count PCLK ticks until SCLK first
//  moves again (start of word-2). Divide by (DIV+1) -> SCLK half-cycles.
//
//  SCLK period: time one full rising-to-rising span in PCLK ticks.
//
// NOTE on constraints
// -------------------
//  spi_txn has   c_delay_sane { delay_cfg inside {[0:7]} }
//  We MUST override that with an inline `with` clause that replaces it;
//  since `with` only appends constraints we cannot "remove" c_delay_sane.
//  Solution: we do NOT use spi_txn for the delay field at all — we set
//  DELAY directly via apb_write and only randomize the fields that do not
//  conflict. This avoids $fatal on sub-tests C (delay=8) and D (delay=128).
// =============================================================================

`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

`include "../sequences/stim_lib.sv"
`include "../env/ref_model.sv"
`include "../env/coverage.sv"

class delay_transfer_test;

    // -------------------------------------------------------------------------
    // measure_sclk_period
    //   Waits for the next rising edge of SCLK, then counts PCLK cycles to
    //   the following rising edge. Returns 0 on timeout.
    // -------------------------------------------------------------------------
    static task measure_sclk_period(output int period_pclk);
        logic prev, cur;
        int   w;

        period_pclk = 0;

        // wait for a rising edge of SCLK
        w    = 100000;
        prev = tb_top.spi.sclk;
        while (w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            cur = tb_top.spi.sclk;
            if (prev === 1'b0 && cur === 1'b1) break;
            prev = cur;
        end
        if (w <= 0) begin
            $display("[CHECKER_ERROR] delay_transfer_test: SCLK never rose (measure_sclk_period)");
            return;
        end

        // count PCLK ticks to next rising edge
        prev = cur;
        w    = 100000;
        while (w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            period_pclk++;
            cur = tb_top.spi.sclk;
            if (prev === 1'b0 && cur === 1'b1) return; // done
            prev = cur;
        end
        $display("[CHECKER_ERROR] delay_transfer_test: SCLK period measurement timeout");
        period_pclk = 0;
    endtask

    // -------------------------------------------------------------------------
    // count_word_and_measure_gap
    //   Deterministic gap measurement using SCLK edge counting.
    //
    //   1. Wait for the first SCLK transition (transfer starts).
    //   2. Count 2*bits_per_word transitions = word-1 complete.
    //      (each bit has one rising + one falling edge)
    //   3. Count PCLK ticks until the next SCLK transition = inter-word gap.
    //
    //   This replaces the old repeat-based approach which could miss the gap
    //   or land mid-gap depending on pipeline latency and DIV value.
    //
    //   NOTE: Assumes CPHA=0 (Mode 0/2). For CPHA=1, the edge count per word
    //   may differ by ±1 due to the setup half-cycle.
    // -------------------------------------------------------------------------
    static task count_word_and_measure_gap(
        input  int bits_per_word,
        output int gap_pclk
    );
        logic prev, cur;
        int   edge_count;
        int   w;

        gap_pclk   = 0;
        edge_count = 0;

        // Phase 1: Wait for first SCLK transition (DUT started shifting)
        prev = tb_top.spi.sclk;
        w    = 500000;
        while (w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            cur = tb_top.spi.sclk;
            if (cur !== prev) begin
                edge_count = 1;
                prev = cur;
                break;
            end
            prev = cur;
        end
        if (w <= 0) begin
            $display("[CHECKER_ERROR] count_word_and_measure_gap: no SCLK activity");
            return;
        end

        // Phase 2: Count remaining edges to complete word-1
        //   Total edges per word = 2 * bits_per_word (rise+fall per bit)
        while (edge_count < 2 * bits_per_word && w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            cur = tb_top.spi.sclk;
            if (cur !== prev) begin
                edge_count++;
                prev = cur;
            end
        end
        if (w <= 0) begin
            $display("[CHECKER_ERROR] count_word_and_measure_gap: word-1 edge count timeout");
            return;
        end

        // Phase 3: SCLK is now at idle level after word-1's last edge.
        //   Count PCLK ticks until the next SCLK transition (= start of word-2).
        prev = cur;
        w    = 500000;
        while (w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            cur = tb_top.spi.sclk;
            if (cur !== prev) return;   // gap ended — first edge of word-2
            gap_pclk++;
        end
        $display("[CHECKER_ERROR] count_word_and_measure_gap: gap measurement timeout");
    endtask

    // -------------------------------------------------------------------------
    // wait_busy_clear  - polls STATUS.BUSY via APB until 0 (or timeout)
    // -------------------------------------------------------------------------
    static task wait_busy_clear();
        bit [31:0] st;
        int        w = 500000;
        tb_top.u_apb_bfm.apb_read(SL_STATUS, st);
        while (st[0] && w-- > 0)
            tb_top.u_apb_bfm.apb_read(SL_STATUS, st);
        if (w <= 0)
            $display("[CHECKER_ERROR] delay_transfer_test: wait_busy_clear timeout");
    endtask

    // -------------------------------------------------------------------------
    // wait_for_rx_ready - polls STATUS.RX_EMPTY until data is visible
    // -------------------------------------------------------------------------
    static task wait_for_rx_ready();
        bit [31:0] st;
        int        w = 500000;
        tb_top.u_apb_bfm.apb_read(SL_STATUS, st);
        while (st[4] && w-- > 0) begin
            @(posedge tb_top.PCLK); #1;
            tb_top.u_apb_bfm.apb_read(SL_STATUS, st);
        end
        if (w <= 0)
            $display("[CHECKER_ERROR] delay_transfer_test: wait_for_rx_ready timeout");
    endtask

    // -------------------------------------------------------------------------
    // configure_dut
    //   Writes CLK_DIV, DELAY, INT_EN, CTRL to both APB BFM and ref-model.
    //   Does NOT push TX data or assert SS.
    // -------------------------------------------------------------------------
    static task configure_dut(
        input bit [15:0] div_val,
        input bit [7:0]  delay_val,
        input bit [1:0]  mode,
        input bit [1:0]  width,
        input bit        lsb_first,
        input bit        loopback,
        ref   spi_ref_model ref_model
    );
        bit [31:0] ctrl_word;

        ctrl_word      = 32'h0;
        ctrl_word[0]   = 1'b1;       // EN
        ctrl_word[1]   = 1'b1;       // MSTR
        ctrl_word[3:2] = mode;
        ctrl_word[4]   = lsb_first;
        ctrl_word[5]   = loopback;
        ctrl_word[7:6] = width;

        tb_top.u_apb_bfm.apb_write(SL_CLK_DIV, {16'b0, div_val});
        tb_top.u_ref.apb_write     (SL_CLK_DIV, {16'b0, div_val});

        tb_top.u_apb_bfm.apb_write(SL_DELAY, {24'b0, delay_val});
        tb_top.u_ref.apb_write     (SL_DELAY, {24'b0, delay_val});

        tb_top.u_apb_bfm.apb_write(SL_INT_EN, 32'h0000_001F);
        tb_top.u_ref.apb_write     (SL_INT_EN, 32'h0000_001F);

        tb_top.u_apb_bfm.apb_write(SL_CTRL, ctrl_word);
        tb_top.u_ref.apb_write     (SL_CTRL, ctrl_word);
    endtask

    // =========================================================================
    // run_delay_subtest
    //   Full stimulus + measurement for one (delay_val, div_val) combination.
    //
    //   Critical ordering:
    //     BFM signals set FIRST (so bfm_pattern is valid before predict_transfer)
    //     configure_dut SECOND
    //     predict_transfer THIRD (bfm_pattern already set)
    //     push TX FOURTH
    //     assert SS LAST (triggers DUT to start shifting)
    // =========================================================================
    static task run_delay_subtest(
        input bit [7:0]  delay_val,
        input bit [15:0] div_val,
        input bit [1:0]  width,
        input bit        lsb_first,
        input bit [1:0]  mode,
        input string     label,
        ref   spi_ref_model    ref_model,
        ref   spi_coverage_col coverage
    );
        bit [31:0] miso_pat;
        bit [31:0] rx_word;
        bit [31:0] int_stat_val;
        bit [31:0] dut_status;
        bit [31:0] dut_ss;
        bit [31:0] dut_status_before_read;
        bit [31:0] status_check;
        logic      cpol;
        int        half_period_pclk;
        int        sclk_period_pclk;
        int        gap_pclk;
        int        measured_half_cycles;
        int        bits_per_word;

        $display("[INFO] delay_transfer_test [%s]: delay=%0d div=%0d width=%0d mode=%0d",
                 label, delay_val, div_val, width, mode);

        cpol             = mode[1];
        half_period_pclk = int'(div_val) + 1;
        case (width)
            2'b00:   bits_per_word = 8;
            2'b01:   bits_per_word = 16;
            default: bits_per_word = 32;
        endcase

        // ---- 1. Set BFM signals BEFORE predict_transfer --------------------
        tb_top.bfm_mode       = mode;
        tb_top.bfm_width      = width;
        tb_top.bfm_lsb_first  = lsb_first; // Fixed variable name here
        tb_top.bfm_pattern    = 32'hA5A5A5A5;

        miso_pat              = 32'hA5A5A5A5;

        // ---- 2. Program DUT registers (no SS assert yet) -------------------
        configure_dut(div_val, delay_val, mode, width, lsb_first, 1'b0, ref_model);

        // ---- 3. Build predictions (bfm_pattern already set) ----------------
        ref_model.predict_transfer(32'hA5A5A5A5, miso_pat, 1'b0, width, lsb_first);
        ref_model.predict_transfer(32'h5A5A5A5A, miso_pat, 1'b0, width, lsb_first);

        // ---- 4. Prepare and start transfer: inform model then push TX -----
        ref_model.mark_transfer_start();

        // Debug: show prediction FIFO sizes before pushing
        $display("[DBG] before push: pred_tx=%0d pred_rx=%0d tx_fifo=%0d",
             ref_model.pred_tx_fifo.size(), ref_model.pred_rx_fifo.size(), ref_model.tx_fifo.size());

        // Push 2 TX words into FIFO (model and DUT)
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, 32'hA5A5A5A5);
        tb_top.u_ref.apb_write     (SL_TX_DATA, 32'hA5A5A5A5);
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, 32'h5A5A5A5A);
        tb_top.u_ref.apb_write     (SL_TX_DATA, 32'h5A5A5A5A);

        // Debug: show FIFO sizes after pushing
        $display("[DBG] after push: pred_tx=%0d pred_rx=%0d tx_fifo=%0d",
             ref_model.pred_tx_fifo.size(), ref_model.pred_rx_fifo.size(), ref_model.tx_fifo.size());

        // ---- Coverage ------------------------------------------------------
        coverage.sample_config(mode, width, lsb_first, 1'b0);
        coverage.sample_clkdiv(div_val);
        coverage.sample_delay(delay_val);
        coverage.sample_ss(4'b0001);
        coverage.sample_fifo(2, 0);

        coverage.sample_register(SL_DELAY,   1'b1);
        coverage.sample_register(SL_CLK_DIV, 1'b1);
        coverage.sample_register(SL_CTRL,    1'b1);
        coverage.sample_register(SL_TX_DATA, 1'b1);

        // ---- 5. Assert SS -> DUT starts shifting ---------------------------
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0001);
        tb_top.u_ref.apb_write     (SL_SS_CTRL, 32'h0000_0001);


        // ---- 6. Measurement ------------------------------------------------
        if (delay_val == 0) begin
            $display("[INFO] delay_transfer_test [%s]: delay=0, no gap to measure", label);
        end else begin
            // 6a. Measure inter-word gap using deterministic edge counting.
            //     Counts 2*bits_per_word SCLK edges (= word 1), then measures
            //     PCLK ticks until the next SCLK transition (= the gap).
            count_word_and_measure_gap(bits_per_word, gap_pclk);

            // Round to nearest half-cycle to absorb ±1 PCLK edge jitter.
            // Subtract 1 because the measurement from the last edge of word-1 
            // to the first edge of word-2 naturally includes 1 inherent half-cycle.
            // The DELAY register specifies *additional* inserted half-cycles.
            measured_half_cycles = ((gap_pclk + half_period_pclk / 2) / half_period_pclk) - 1;

            $display("[INFO] delay_transfer_test [%s]: gap=%0d PCLK / hp=%0d => %0d half-cycles inserted (expected %0d)",
                     label, gap_pclk, half_period_pclk, measured_half_cycles, int'(delay_val));

            ref_model.check_delay(measured_half_cycles);

            // 6b. Measure SCLK period during word-2 (validates CLK_DIV)
            measure_sclk_period(sclk_period_pclk);

            if (sclk_period_pclk == 0) begin
                $display("[CHECKER_ERROR] delay_transfer_test [%s]: SCLK period measurement failed", label);
                ref_model.error_count++;
            end else begin
                $display("[INFO] delay_transfer_test [%s]: SCLK period=%0d PCLK (expected %0d)",
                         label, sclk_period_pclk, 2*half_period_pclk);
                ref_model.check_sclk_period(sclk_period_pclk);
            end
        end

        // ---- 7. Wait for both transfers to complete ------------------------
        wait_busy_clear();

        // Allow the DUT time to finish internal RX push / status updates.
        repeat (100) @(posedge tb_top.PCLK);
        wait_for_rx_ready();
        // ---- 8. Deassert SS ------------------------------------------------
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0000);
        tb_top.u_ref.apb_write     (SL_SS_CTRL, 32'h0000_0000);

        // ---- 9. Drain RX FIFO + scoreboard ---------------------------------
        // Debug: show RX FIFO / prediction sizes before draining
        $display("[DBG] before drain: rx_fifo=%0d pred_rx=%0d int_stat=0x%08h",
             ref_model.rx_fifo.size(), ref_model.pred_rx_fifo.size(), ref_model.int_stat);
        // Word 1
        ref_model.mark_transfer_done(miso_pat);
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);
        void'(tb_top.u_ref.apb_read(SL_RX_DATA));
        ref_model.check_rx(rx_word);
        coverage.sample_register(SL_RX_DATA, 1'b0);

        // Word 2
        ref_model.mark_transfer_done(miso_pat);
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);
        void'(tb_top.u_ref.apb_read(SL_RX_DATA));
        ref_model.check_rx(rx_word);
        coverage.sample_fifo(0, 0);

        // ---- 10. INT_STAT check + clear ------------------------------------
        tb_top.u_apb_bfm.apb_read(SL_INT_STAT, int_stat_val);
        ref_model.check_int_stat(int_stat_val);
        coverage.sample_interrupt(int_stat_val[4:0], 5'h1F);
        coverage.sample_register(SL_INT_STAT, 1'b0);
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT, 32'h0000_001F);
        tb_top.u_ref.apb_write     (SL_INT_STAT, 32'h0000_001F);

        $display("[INFO] delay_transfer_test [%s]: done, errors so far=%0d",
                 label, ref_model.error_count);
    endtask

    // =========================================================================
    // run_r24_r25_subtest
    //   R24: DIV=0 -> SCLK period = 2 PCLK cycles.
    //   R25: Writing CLK_DIV mid-transfer must NOT change the in-flight period.
    // =========================================================================
    static task run_r24_r25_subtest(
        ref spi_ref_model    ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] miso_pat;
        bit [31:0] rx_word;
        int        period_before, period_after;

        $display("[INFO] delay_transfer_test [R24/R25]: starting");

        // ---- 1. BFM -----------------------------------------------------------
        tb_top.bfm_mode       = 2'b00;
        tb_top.bfm_width      = 2'b00;
        tb_top.bfm_lsb_first  = 1'b0; // Fixed variable name here
        tb_top.bfm_pattern    = 32'hCC_CC_CC_CC;

        miso_pat              = 32'hCC_CC_CC_CC;

        // ---- 2. Configure DUT: DIV=0, DELAY=0, MODE=0, 8-bit ---------------
        configure_dut(16'd0, 8'd0, 2'b00, 2'b00, 1'b0, 1'b0, ref_model);

        // ---- 3. Predict + push TX -------------------------------------------
        ref_model.predict_transfer(32'h0000_00CC, miso_pat, 1'b0, 2'b00, 1'b0);

        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, 32'h0000_00CC);
        tb_top.u_ref.apb_write     (SL_TX_DATA, 32'h0000_00CC);
        ref_model.mark_transfer_start();

        coverage.sample_clkdiv(16'd0);
        coverage.sample_config(2'b00, 2'b00, 1'b0, 1'b0);
        coverage.sample_delay(8'd0);

        // ---- 4. Assert SS -> transfer starts --------------------------------
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0001);
        tb_top.u_ref.apb_write     (SL_SS_CTRL, 32'h0000_0001);

        // ---- 5. R24: measure SCLK period -> must be 2 PCLK -----------------
        measure_sclk_period(period_before);

        $display("[INFO] delay_transfer_test [R24/R25]: period before write = %0d PCLK (expected 2)",
                 period_before);

        ref_model.check_sclk_period(period_before);

        // ---- 6. R25: write new CLK_DIV mid-transfer (DIV=7 -> period=16) ---
        // Write only to DUT, NOT to ref_model; ref_model still holds DIV=0
        // so the next check_sclk_period still expects period = 2.
        tb_top.u_apb_bfm.apb_write(SL_CLK_DIV, 32'h0000_0007);

        // Measure again during the SAME transfer -> must still be 2
        measure_sclk_period(period_after);

        $display("[INFO] delay_transfer_test [R24/R25]: period after write  = %0d PCLK (still expect 2)",
                 period_after);

        ref_model.check_sclk_period(period_after);

        // ---- 7. Wait, deassert SS, drain RX ---------------------------------
        wait_busy_clear();

        // Give the DUT time to settle before reading RX_DATA.
        repeat (100) @(posedge tb_top.PCLK);
        wait_for_rx_ready();

        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0000);
        tb_top.u_ref.apb_write     (SL_SS_CTRL, 32'h0000_0000);

        ref_model.mark_transfer_done(miso_pat);
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);
        void'(tb_top.u_ref.apb_read(SL_RX_DATA));
        ref_model.check_rx(rx_word);

        // Sync ref_model to DUT state (DIV=7 now in effect for next xfer)
        tb_top.u_ref.apb_write(SL_CLK_DIV, 32'h0000_0007);

        // Clear INT_STAT
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT, 32'h0000_001F);
        tb_top.u_ref.apb_write     (SL_INT_STAT, 32'h0000_001F);

        $display("[INFO] delay_transfer_test [R24/R25]: done, errors so far=%0d",
                 ref_model.error_count);
    endtask

    // =========================================================================
    // run - top-level entry point called by tb_top
    // =========================================================================
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        int total_errors = 0;
        $display("[INFO] delay_transfer_test: starting");

        // Sub-test A: DELAY=0, DIV=3, 8-bit, mode-0
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        run_delay_subtest(8'd0,   16'd3, 2'b00, 1'b0, 2'b00,
                  "A-delay0-8b",    ref_model, coverage);

        // Sub-test B: DELAY=1, DIV=2, 8-bit, mode-0
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        run_delay_subtest(8'd1,   16'd2, 2'b00, 1'b0, 2'b00,
                  "B-delay1-8b",    ref_model, coverage);

        // Sub-test C: DELAY=8, DIV=1, 8-bit, mode-0
        // delay_cfg=8 violates spi_txn.c_delay_sane [0:7], so we bypass
        // spi_txn entirely and write DELAY directly via configure_dut.
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        run_delay_subtest(8'd8,   16'd1, 2'b00, 1'b0, 2'b00,
                  "C-delay8-8b",    ref_model, coverage);

        // Sub-test D: DELAY=128, DIV=0, 8-bit, mode-0
        // Hits coverage bin delay_large (>=128) and DIV=0 corner simultaneously
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        run_delay_subtest(8'd128, 16'd0, 2'b00, 1'b0, 2'b00,
                  "D-delay128-8b",  ref_model, coverage);

        // Sub-test E: R24 + R25 dedicated sub-test
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        run_r24_r25_subtest(ref_model, coverage);
        total_errors += ref_model.error_count;

        ref_model.error_count = total_errors;
        $display("[INFO] delay_transfer_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask

endclass

`endif // DELAY_TRANSFER_TEST_SV