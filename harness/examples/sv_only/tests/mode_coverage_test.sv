// =============================================================================
// mode_coverage_test.sv
// -----------------------------------------------------------------------------
// TC_02  |  Requirements: All 4 modes × 3 widths × 2 orderings = 24 combos
// Purpose: Iterate through the cross product of all SPI modes, transfer widths,
// and bit orderings to ensure full configuration coverage, using the slave BFM.
// =============================================================================

`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV

`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class mode_coverage_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [1:0] modes[4]  = '{2'b00, 2'b01, 2'b10, 2'b11};
        bit [1:0] widths[3] = '{2'b00, 2'b01, 2'b10};
        bit       orders[2] = '{1'b0, 1'b1};

        spi_txn rand_txn;
        bit [31:0] rx_word;
        bit [31:0] captured_mosi;
        int test_idx = 1;

        $display("[INFO] mode_coverage_test: starting");

        foreach(modes[m]) begin
            foreach(widths[w]) begin
                foreach(orders[o]) begin
                    rand_txn = new();
                    // Use constrained randomization to hit the exact combo while 
                    // randomizing tx_data, clk_div, and delay_cfg
                    if (!rand_txn.randomize() with { 
                        loopback  == 1'b0; 
                        ss_en     == 4'b0001; 
                        mode      == modes[m];
                        width     == widths[w];
                        lsb_first == orders[o];
                    }) begin
                        $fatal(1, "Failed to randomize txn");
                    end

                    // 1. Clean state before each transfer
                    spi_sequence_lib::reset_dut();
                    ref_model.reset();

                    // 2. Configure BFM
                    tb_top.bfm_mode      = rand_txn.mode;
                    tb_top.bfm_pattern   = $urandom();
                    tb_top.bfm_lsb_first = rand_txn.lsb_first;
                    tb_top.bfm_width     = rand_txn.width;

                    // 3. Configure DUT
                    spi_sequence_lib::configure_dut(rand_txn);

                    // 4. Predict
                    ref_model.predict_transfer(
                        .tx_data      (rand_txn.tx_data),
                        .miso_pattern (tb_top.bfm_pattern),
                        .loopback     (1'b0),
                        .width        (rand_txn.width),
                        .lsb_first    (rand_txn.lsb_first)
                    );
                    ref_model.mark_transfer_start();

                    // 5. Execute
                    spi_sequence_lib::push_single(rand_txn);
                    spi_sequence_lib::target_ss(rand_txn.ss_en);
                    spi_sequence_lib::wait_idle();
                    spi_sequence_lib::target_ss(4'b0000); // De-assert SS

                    // 6. Fetch RX data and finalize prediction
                    spi_sequence_lib::apb_read_sync(8'h0C, rx_word);
                    ref_model.mark_transfer_done(tb_top.bfm_pattern);

                    // 7. Scoreboard Checks (MISO stream)
                    ref_model.check_rx(rx_word);

                    // Scoreboard Checks (MOSI stream captured by BFM)
                    if (tb_top.u_spi_bfm.mosi_q.size() > 0) begin
                        captured_mosi = tb_top.u_spi_bfm.mosi_q.pop_front();
                        ref_model.check_tx(captured_mosi);
                    end else begin
                        $display("[SCOREBOARD_ERROR] mode_coverage_test: BFM did not capture any MOSI data!");
                        ref_model.error_count++;
                    end

                    // 8. Sample Coverage
                    coverage.sample_config(rand_txn.mode, rand_txn.width, rand_txn.lsb_first, 1'b0);

                    $display("[INFO] mode_coverage_test: [%0d/24] Mode=%0d Width=%0d LSB=%0b - Pass", 
                             test_idx, modes[m], widths[w], orders[o]);
                    test_idx++;
                end
            end
        end

        if (ref_model.error_count == 0)
            $display("[TEST_PASSED] mode_coverage_test");
        else
            $display("[TEST_FAILED] mode_coverage_test errors=%0d", ref_model.error_count);

    endtask
endclass

`endif
