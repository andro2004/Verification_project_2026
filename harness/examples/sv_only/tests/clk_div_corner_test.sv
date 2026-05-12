// =============================================================================
// clk_div_corner_test.sv  (Owner: M5)
// -----------------------------------------------------------------------------
// Exercises CLK_DIV at corner values: 0, 1, 2, 3, 255, 1024, 65535.
// Measures the actual SCLK period and compares it against the reference model's
// predicted formula: period = 2 * (DIV + 1).
// =============================================================================

`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class clk_div_corner_test;

    static task do_clkdiv_xfer(
        input  string           label,
        input  bit [15:0]       div_val,
        ref    spi_ref_model    ref_model,
        ref    spi_coverage_col coverage
    );
        spi_txn   txn;
        bit [31:0] rx_word;
        int        start_time, end_time, measured_pclk_cycles;

        // Reset DUT and Model
        spi_sequence_lib::reset_dut();
        ref_model.reset();

        // Build transaction
        txn = new();
        txn.mode       = 2'b00;
        txn.width      = 2'b00; // 8-bit
        txn.lsb_first  = 1'b0;
        txn.loopback   = 1'b0;
        txn.clk_div    = div_val;
        txn.delay_cfg  = 8'd0;
        txn.ss_en      = 4'b0001;
        txn.tx_data    = 32'h0000_00AA; 

        // Setup Slave BFM
        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_pattern   = 32'h0000_0055;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_width     = 2'b00;

        // Configure DUT
        spi_sequence_lib::configure_dut(txn);

        // Predict RX
        ref_model.predict_transfer(
            .tx_data      (txn.tx_data),
            .miso_pattern (tb_top.bfm_pattern),
            .loopback     (txn.loopback),
            .width        (txn.width),
            .lsb_first    (txn.lsb_first)
        );

        // Mark transfer start
        ref_model.mark_transfer_start();

        fork
            begin
                // Thread 1: drive stimulus
                spi_sequence_lib::push_single(txn);
                spi_sequence_lib::target_ss(txn.ss_en);
                spi_sequence_lib::wait_idle();
                spi_sequence_lib::target_ss(4'b0000);
            end
            begin
                // Thread 2: measure SCLK period
                @(posedge tb_top.u_wrap.u_dut.u_core.SCLK);
                start_time = $time;
                @(posedge tb_top.u_wrap.u_dut.u_core.SCLK);
                end_time = $time;
                measured_pclk_cycles = (end_time - start_time) / 10;
            end
        join

        // Mark transfer done
        ref_model.mark_transfer_done(tb_top.bfm_pattern);

        // Read RX and check
        tb_top.u_apb_bfm.apb_read(8'h0C, rx_word);
        ref_model.check_rx(rx_word);

        // Check SCLK period
        ref_model.check_sclk_period(measured_pclk_cycles);

        // Sample coverage
        coverage.sample_clkdiv(div_val);

        $display("[INFO] clk_div_corner_test: %s (DIV=%0d), measured period = %0d PCLK cycles",
                 label, div_val, measured_pclk_cycles);
    endtask

    static task test_65535(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn txn;
        int start_time, end_time, measured_pclk_cycles;
        
        spi_sequence_lib::reset_dut();
        ref_model.reset();
        
        txn = new();
        txn.mode       = 2'b00;
        txn.width      = 2'b00;
        txn.lsb_first  = 1'b0;
        txn.loopback   = 1'b0;
        txn.clk_div    = 16'd65535;
        txn.delay_cfg  = 8'd0;
        txn.ss_en      = 4'b0001;
        txn.tx_data    = 32'h0000_00AA;

        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_pattern   = 32'h0000_0055;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_width     = 2'b00;

        spi_sequence_lib::configure_dut(txn);
        
        ref_model.predict_transfer(txn.tx_data, tb_top.bfm_pattern, txn.loopback, txn.width, txn.lsb_first);
        ref_model.mark_transfer_start();

        spi_sequence_lib::push_single(txn);
        spi_sequence_lib::target_ss(txn.ss_en);

        // --- NEW: Test R25 (Held for duration) ---
        // Change CLK_DIV mid-transfer via APB. SCLK period should NOT change!
        // We write 0 (fastest clk) but it should still be operating at 65535 period.
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0000); 

        // Wait for exactly one period and then abort to save simulation time
        @(posedge tb_top.u_wrap.u_dut.u_core.SCLK);
        start_time = $time;
        @(posedge tb_top.u_wrap.u_dut.u_core.SCLK);
        end_time = $time;
        measured_pclk_cycles = (end_time - start_time) / 10;
        
        // Disable DUT to abort the transfer and clear state
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0); // CTRL.EN=0
        ref_model.apb_write(8'h00, 32'h0); // Sync model
        
        ref_model.check_sclk_period(measured_pclk_cycles);
        coverage.sample_clkdiv(16'd65535);
        $display("[INFO] clk_div_corner_test: div_65535, measured period = %0d PCLK cycles", measured_pclk_cycles);
    endtask

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        $display("[INFO] clk_div_corner_test: starting");

        do_clkdiv_xfer("div_0", 16'd0, ref_model, coverage);
        do_clkdiv_xfer("div_1", 16'd1, ref_model, coverage);
        do_clkdiv_xfer("div_2", 16'd2, ref_model, coverage);
        do_clkdiv_xfer("div_3", 16'd3, ref_model, coverage);
        do_clkdiv_xfer("div_255", 16'd255, ref_model, coverage);
        do_clkdiv_xfer("div_1024", 16'd1024, ref_model, coverage);
        
        $display("[INFO] clk_div_corner_test: testing 65535 specifically for 1 cycle");
        test_65535(ref_model, coverage);

        $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // CLK_DIV_CORNER_TEST_SV
