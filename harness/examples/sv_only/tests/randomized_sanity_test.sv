// =============================================================================
// randomized_sanity_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Companion to sanity_test. Same end-to-end checking, but the configuration
// is built from a randomised `spi_txn` (sequences/stim_lib.sv) instead of
// hard-coded literals. Use this as a template for your own constrained-random
// tests.
//
// What this test demonstrates:
//   1. How to instantiate spi_txn:               t = new();
//   2. How to constrain it inline at randomize:  t.randomize() with { ... };
//   3. How to print a transaction for debug:     $display(... t.sprint());
//   4. How to drive the randomised fields onto the DUT through the APB BFM.
//   5. How to keep the predictor in lock-step with the random TX byte.
//   6. How to sample functional coverage from the same fields.
//
// IMPORTANT - constraint scoping:
//
//   The starter scaffold has known limitations that students will lift later:
//     * spi_slave_bfm only supports mode 0 (CPOL=0, CPHA=0).
//     * spi_slave_bfm is hard-wired MSB-first.
//     * spi_ref_model only predicts a single 8-bit transfer.
//
//   For this scaffolded demonstration we therefore PIN the fields the slave
//   BFM cannot follow (mode, lsb_first, width, loopback) and only let the
//   random fields that DON'T affect the predicted RX byte vary (clk_div,
//   delay_cfg, tx_data). That keeps the test deterministic on golden RTL
//   while still showing the randomisation pattern.
//
//   Once you extend spi_slave_bfm to handle modes 1..3 and LSB-first, just
//   relax the corresponding constraint in your own variant of this test.
//
// Public API: randomized_sanity_test::run(ref_model, coverage);
// =============================================================================

`ifndef RANDOMIZED_SANITY_TEST_SV
`define RANDOMIZED_SANITY_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"
class randomized_sanity_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);

        spi_txn   t;
        bit [31:0] ctrl_word;
        bit [31:0] rd;
        int        seed;
        bit [31:0] rand_pat;

        $display("[INFO] randomized_sanity_test: starting");

        t = new();
        if ($value$plusargs("SEED=%d", seed))
            t.srandom(seed);

        repeat(20) begin
            // Step 2 - randomise with inline constraints.
            // We unpin mode, width, lsb_first, and loopback because our BFM and predictor support them.
            if (!t.randomize() with {
                    clk_div   inside {[1:32]};
                }) begin
                $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                ref_model.error_count++;
                return;
            end

            rand_pat = $urandom();

            // Step 3 - print the randomised transaction.
            $display("[INFO] randomized_sanity_test: %s", t.sprint());

            // Keep the slave BFM's mode in sync with the random mode.
            tb_top.bfm_mode      = t.mode;
            tb_top.bfm_pattern   = rand_pat;
            tb_top.bfm_lsb_first = t.lsb_first;
            tb_top.bfm_width     = t.width;

            // Step 4 - drive the randomised fields through the APB BFM.
            ctrl_word = 32'h0;
            ctrl_word[0]   = 1'b1;          // EN
            ctrl_word[1]   = 1'b1;          // MSTR
            ctrl_word[3:2] = t.mode;
            ctrl_word[4]   = t.lsb_first;
            ctrl_word[5]   = t.loopback;
            ctrl_word[7:6] = t.width;

            tb_top.u_apb_bfm.apb_write(8'h00, ctrl_word);                 // CTRL
            tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});        // CLK_DIV
            tb_top.u_apb_bfm.apb_write(8'h20, {24'h0, t.delay_cfg});      // DELAY
            tb_top.u_apb_bfm.apb_write(8'h18, 32'h0000_001F);             // INT_EN

            // Step 5 - tell the predictor what to expect BEFORE pushing TX.
            ref_model.predict_transfer(.tx_data(t.tx_data),
                                       .miso_pattern(rand_pat),
                                       .loopback(t.loopback),
                                       .width(t.width),
                                       .lsb_first(t.lsb_first));

            ref_model.mark_transfer_start();

            // Step 6 - sample functional coverage.
            coverage.sample_config(.mode(t.mode),
                                   .lsb_first(t.lsb_first),
                                   .width(t.width),
                                   .loopback(t.loopback));

            // Step 7 - push TX and assert randomized SS lanes.
            tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);                 // TX_DATA
            tb_top.u_apb_bfm.apb_write(8'h14, {24'h0, 4'b0000, t.ss_en}); // SS_CTRL

            // Step 8 - busy-poll STATUS.BUSY until the transfer drains.
            repeat (5000) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);                     // STATUS
                if (rd[0] == 1'b0) break;
            end

            ref_model.mark_transfer_done(rand_pat);

            // Step 9 - read RX_DATA and let the scoreboard check it.
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);                         // RX_DATA
            ref_model.check_rx(rd);

            // Step 10 - Additional checks to catch possible bugs
            tb_top.u_apb_bfm.apb_read(8'h04, rd);                         // STATUS
            ref_model.check_status(rd);

            tb_top.u_apb_bfm.apb_read(8'h1C, rd);                         // INT_STAT
            ref_model.check_int_stat(rd);

            // Cleanup: clear interrupts and deassert SS
            tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_001F);             // W1C
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
            
            // Disable controller to reset internal state for next loop
            tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);
        end

        $display("[INFO] randomized_sanity_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask

endclass

`endif // RANDOMIZED_SANITY_TEST_SV
