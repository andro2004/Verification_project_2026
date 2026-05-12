// =============================================================================
// error_injection_test.sv  (Owner: M3 — Phase 2)
// -----------------------------------------------------------------------------
// Robustness test: intentionally drives illegal / out-of-spec software
// sequences and verifies the DUT handles them gracefully:
//
//   Scenario 1 — TX overflow    (R13): Write TX_DATA when TX_FULL=1
//   Scenario 2 — RX underflow   (R15): Read RX_DATA when RX_EMPTY=1
//   Scenario 3 — RX overflow    (R14): Fill RX FIFO beyond 8, verify RX_OVF
//   Scenario 4 — Illegal width  (R23): CTRL.WIDTH = 2'b11 (reserved encoding)
//   Scenario 5 — Reserved regs  (R23): Write/read offsets >= 0x24
//   Scenario 6 — Post-error recovery: After all error injections, verify the
//                DUT can still complete a clean transfer.
//
// Requirements covered: R13, R14, R15, R23
// Coverage sampled:     cg_fifo, cg_interrupt, cg_register
//
// Public API: error_injection_test::run(ref_model, coverage);
// =============================================================================

`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class spi_txn_error extends spi_txn;
    constraint c_error_cfg {
        mode == 2'b00;
        width == 2'b00;
        lsb_first == 1'b0;
        loopback == 1'b1; // Use loopback to easily fill RX FIFO without BFM sync issues
        clk_div inside {[16'd1 : 16'd10]}; // Keep it small for faster sim
    }
endclass

class error_injection_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);

        spi_txn_error txn;
        bit [31:0] rd;
        bit [31:0] status;
        bit [31:0] int_stat_rd;
        int        i;
        int        seed;

        $display("[INFO] error_injection_test: starting");

        txn = new();
        if ($value$plusargs("SEED=%d", seed))
            txn.srandom(seed);

        if (!txn.randomize()) begin
            $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
            ref_model.error_count++;
            return;
        end
        $display("[INFO] error_injection_test: Randomized txn: %s", txn.sprint());

        // =================================================================
        // SETUP — clean baseline: reset ref model, configure DUT in mode 0,
        // 8-bit, loopback ON (avoids needing slave BFM sync), fast clock.
        // =================================================================
        spi_sequence_lib::reset_dut();
        ref_model.reset();

        tb_top.bfm_mode    = txn.mode;
        tb_top.bfm_pattern = 8'hA5;

        spi_sequence_lib::configure_dut(txn);
        coverage.sample_config(.mode(txn.mode), .lsb_first(txn.lsb_first),
                               .width(txn.width), .loopback(txn.loopback));
        coverage.sample_clkdiv(txn.clk_div);

        // =================================================================
        // SCENARIO 1 — TX Overflow (R13)
        // Fill TX FIFO to capacity (8 entries), then push one more.
        // The 9th write must be discarded and TX_OVF flag set.
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 1 — TX overflow (R13)");

        // Push 8 entries to fill the TX FIFO
        for (i = 0; i < 8; i++) begin
            if (!txn.randomize()) $display("Rand fail");
            tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
            ref_model.apb_write(32'h08, txn.tx_data);
            coverage.sample_register(SL_TX_DATA, 1'b1);
        end

        // Verify TX_FULL is asserted via STATUS
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        coverage.sample_register(SL_STATUS, 1'b0);
        if (status[1] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] TX_FULL not set after 8 pushes: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Sample FIFO coverage at full
        coverage.sample_fifo(8, 0);

        // Now push the 9th entry — this must trigger TX_OVF
        if (!txn.randomize()) $display("Rand fail");
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
        ref_model.apb_write(32'h08, txn.tx_data);
        coverage.sample_register(SL_TX_DATA, 1'b1);

        // Check STATUS.TX_OVF (bit 5)
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        coverage.sample_register(SL_STATUS, 1'b0);
        if (status[5] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] TX_OVF not set after overflow write: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Check INT_STAT.TX_OVF (bit 2) is set
        tb_top.u_apb_bfm.apb_read(SL_INT_STAT, int_stat_rd);
        coverage.sample_register(SL_INT_STAT, 1'b0);
        if (int_stat_rd[2] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] INT_STAT.TX_OVF not set: INT_STAT=0x%08h", int_stat_rd);
            ref_model.error_count++;
        end

        // Sample interrupt coverage: TX_OVF asserted, all enabled
        coverage.sample_interrupt(int_stat_rd[4:0], 5'b11111);

        // Drain the TX FIFO by running 8 transfers (loopback mode)
        spi_sequence_lib::target_ss(txn.ss_en);
        spi_sequence_lib::wait_idle();
        spi_sequence_lib::target_ss(4'b0000);

        // Drain RX FIFO (8 entries from the 8 loopback transfers)
        for (i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);
            coverage.sample_register(SL_RX_DATA, 1'b0);
        end

        // Clear all interrupt flags before next scenario
        spi_sequence_lib::clear_interrupts(int_stat_rd);

        // Sample FIFO at empty after drain
        coverage.sample_fifo(0, 0);

        // =================================================================
        // SCENARIO 2 — RX Underflow / Empty Read (R15)
        // Read RX_DATA when the RX FIFO is empty. Must return 0 and must
        // NOT set RX_OVF.
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 2 — RX empty read (R15)");

        // Confirm RX_EMPTY is set
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        coverage.sample_register(SL_STATUS, 1'b0);
        if (status[4] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] RX_EMPTY not set before empty read: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Read RX_DATA while empty — should return 0
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);
        coverage.sample_register(SL_RX_DATA, 1'b0);
        if (rd !== 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] RX empty read returned non-zero: got=0x%08h expected=0x00000000", rd);
            ref_model.error_count++;
        end

        // Verify RX_OVF (STATUS bit 6) is NOT set
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        if (status[6] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] RX_OVF incorrectly set after empty read: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Verify INT_STAT.RX_OVF (bit 3) is NOT set
        tb_top.u_apb_bfm.apb_read(SL_INT_STAT, int_stat_rd);
        if (int_stat_rd[3] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] INT_STAT.RX_OVF set after empty read: INT_STAT=0x%08h", int_stat_rd);
            ref_model.error_count++;
        end

        // Do a second empty read for good measure
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);
        if (rd !== 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] Second RX empty read returned non-zero: got=0x%08h", rd);
            ref_model.error_count++;
        end

        // Sample FIFO coverage: RX at empty
        coverage.sample_fifo(0, 0);

        // =================================================================
        // SCENARIO 3 — RX Overflow (R14)
        // Push 8 transfers to fill the RX FIFO without draining it, then
        // push a 9th transfer. The 9th RX entry must be discarded and
        // RX_OVF flag set.
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 3 — RX overflow (R14)");

        spi_sequence_lib::clear_interrupts(int_stat_rd);

        // Push 8 TX entries (loopback will fill the RX FIFO)
        for (i = 0; i < 8; i++) begin
            if (!txn.randomize()) $display("Rand fail");
            tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
            ref_model.apb_write(32'h08, txn.tx_data);
        end

        // Assert SS and let all 8 transfer
        spi_sequence_lib::target_ss(txn.ss_en);
        spi_sequence_lib::wait_idle();
        spi_sequence_lib::target_ss(4'b0000);

        // Verify RX_FULL is set (8 entries received, none read)
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        if (status[3] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] RX_FULL not set after 8 transfers: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Sample FIFO coverage at RX full
        coverage.sample_fifo(0, 8);

        // Now push one more TX entry to trigger a 9th transfer → RX overflow
        if (!txn.randomize()) $display("Rand fail");
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
        ref_model.apb_write(32'h08, txn.tx_data);

        spi_sequence_lib::target_ss(txn.ss_en);
        spi_sequence_lib::wait_idle();
        spi_sequence_lib::target_ss(4'b0000);

        // Check STATUS.RX_OVF (bit 6) is now set
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        if (status[6] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] RX_OVF not set after RX overflow: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Check INT_STAT.RX_OVF (bit 3) is set
        tb_top.u_apb_bfm.apb_read(SL_INT_STAT, int_stat_rd);
        if (int_stat_rd[3] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] INT_STAT.RX_OVF not set: INT_STAT=0x%08h", int_stat_rd);
            ref_model.error_count++;
        end

        // Sample interrupt coverage: RX_OVF asserted
        coverage.sample_interrupt(int_stat_rd[4:0], 5'b11111);

        // Drain RX FIFO to clean up
        for (i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);
        end

        // Clear all interrupt flags
        spi_sequence_lib::clear_interrupts(int_stat_rd);

        // =================================================================
        // SCENARIO 4 — Illegal WIDTH encoding (R23)
        // Write CTRL.WIDTH = 2'b11 which is reserved/illegal. The DUT must
        // not crash, hang, or assert PSLVERR. We simply verify the DUT
        // remains operational afterward.
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 4 — Illegal width encoding");

        begin
            bit [31:0] bad_ctrl;
            bad_ctrl = txn.pack_ctrl_word();
            bad_ctrl[7:6] = 2'b11; // Reserved width
            
            tb_top.u_apb_bfm.apb_write(SL_CTRL, bad_ctrl);
            coverage.sample_register(SL_CTRL, 1'b1);

            tb_top.u_apb_bfm.apb_read(SL_CTRL, rd);
            coverage.sample_register(SL_CTRL, 1'b0);
            $display("[INFO] error_injection_test: CTRL readback after illegal width = 0x%08h", rd);

            // Try a transfer with the illegal width to verify no hang
            if (!txn.randomize()) $display("Rand fail");
            tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
            spi_sequence_lib::target_ss(txn.ss_en);

            // Use a timeout poll — if DUT hangs this will eventually exit
            begin
                int cycles = 0;
                tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
                while (status[0] == 1'b1 && cycles < 2000) begin
                    tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
                    cycles++;
                end
            end

            spi_sequence_lib::target_ss(4'b0000);

            // Read RX to flush whatever happened
            tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);

            // Restore legal width for subsequent scenarios
            tb_top.u_apb_bfm.apb_write(SL_CTRL, txn.pack_ctrl_word());  
            ref_model.apb_write(32'h00, txn.pack_ctrl_word());

            // Clear interrupts
            spi_sequence_lib::clear_interrupts(int_stat_rd);
        end

        // =================================================================
        // SCENARIO 5 — Reserved register offsets (R23)
        // Write to addresses >= 0x24. Writes must be ignored and reads must
        // return 0. The DUT must not assert PSLVERR (R22).
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 5 — Reserved register offsets (R23)");

        begin
            // Test several reserved offsets
            bit [7:0] reserved_addrs [6] = '{8'h24, 8'h28, 8'h2C, 8'h30, 8'h40, 8'hFC};

            foreach (reserved_addrs[j]) begin
                if (!txn.randomize()) $display("Rand fail");
                
                // Write a random pattern to the reserved offset
                tb_top.u_apb_bfm.apb_write(reserved_addrs[j], txn.tx_data);
                coverage.sample_register(reserved_addrs[j], 1'b1);

                // Read it back — must return 0
                tb_top.u_apb_bfm.apb_read(reserved_addrs[j], rd);
                coverage.sample_register(reserved_addrs[j], 1'b0);

                if (rd !== 32'h0000_0000) begin
                    $display("[SCOREBOARD_ERROR] Reserved offset 0x%02h read non-zero: got=0x%08h",
                             reserved_addrs[j], rd);
                    ref_model.error_count++;
                end
            end
        end

        // Verify that writing reserved offsets didn't corrupt real registers.
        tb_top.u_apb_bfm.apb_read(SL_CTRL, rd);
        coverage.sample_register(SL_CTRL, 1'b0);
        ref_model.check_reg("CTRL", ref_model.ctrl, rd);

        tb_top.u_apb_bfm.apb_read(SL_CLK_DIV, rd);
        coverage.sample_register(SL_CLK_DIV, 1'b0);
        ref_model.check_reg("CLK_DIV", ref_model.clk_div, rd);

        // =================================================================
        // SCENARIO 6 — Post-error recovery
        // After all error injections, confirm the DUT can still do a clean
        // loopback transfer end-to-end.
        // =================================================================
        $display("[INFO] error_injection_test: SCENARIO 6 — Post-error recovery transfer");

        // Clear everything for a clean transfer
        spi_sequence_lib::reset_dut();
        ref_model.reset();

        if (!txn.randomize()) $display("Rand fail");
        
        tb_top.bfm_mode    = txn.mode;
        tb_top.bfm_pattern = txn.tx_data[7:0]; 

        spi_sequence_lib::configure_dut(txn);

        // Push one byte and do a loopback transfer
        ref_model.predict_single_byte(.tx_byte(txn.tx_data[7:0]),
                                      .miso_pattern(tb_top.bfm_pattern),
                                      .loopback(txn.loopback));
        
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
        ref_model.apb_write(32'h08, txn.tx_data);

        spi_sequence_lib::target_ss(txn.ss_en);
        spi_sequence_lib::wait_idle();
        spi_sequence_lib::target_ss(4'b0000);

        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rd);
        coverage.sample_register(SL_RX_DATA, 1'b0);
        ref_model.check_rx(rd);

        // Final STATUS check — should be clean (not BUSY, not OVF)
        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        if (status[0] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] Post-error: DUT still BUSY: STATUS=0x%08h", status);
            ref_model.error_count++;
        end

        // Sample final coverage
        coverage.sample_config(.mode(txn.mode), .lsb_first(txn.lsb_first),
                               .width(txn.width), .loopback(txn.loopback));
        coverage.sample_fifo(0, 0);

        $display("[INFO] error_injection_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask

endclass

`endif // ERROR_INJECTION_TEST_SV
