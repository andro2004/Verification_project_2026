// =============================================================================
// fifo_stress_test.sv  (Owner: M3)
// -----------------------------------------------------------------------------
// Purpose: Stress the TX/RX FIFOs. Push 8 entries to fill TX, let them transfer
// to fill RX, overflow both, verify flags (empty, full, overflow), and ensure
// data integrity across the FIFOs using random payloads.
// =============================================================================

`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class fifo_stress_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [31:0] rx_word, status_val, int_stat_val;
        bit [31:0] tx_data_arr[8];
        bit [31:0] tx_ovf_val, rx_ovf_val;
        spi_txn_fifo rand_txn;

        $display("[INFO] fifo_stress_test: starting");

        spi_sequence_lib::reset_dut();
        ref_model.reset();

        // ---------------------------------------------------------------------
        // STEP 0: Configuration
        // ---------------------------------------------------------------------
        rand_txn = new();
        if (!rand_txn.randomize() with { loopback == 1'b1; ss_en == 4'b0001; })
            $fatal(1, "Failed to randomize fifo txn");

        spi_sequence_lib::configure_dut(rand_txn);
        spi_sequence_lib::target_ss(rand_txn.ss_en);

        // Configure the BFM Slave to match the randomized DUT configuration
        tb_top.bfm_mode      = rand_txn.mode;
        tb_top.bfm_pattern   = $urandom();
        tb_top.bfm_lsb_first = rand_txn.lsb_first;
        tb_top.bfm_width     = rand_txn.width;

        // ---------------------------------------------------------------------
        // STEP 1: Fill TX FIFO to capacity (8 items) & Verify TX_FULL
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Filling TX FIFO with 8 items");
        for (int i = 0; i < 8; i++) begin
            tx_data_arr[i] = $urandom();
            tb_top.u_apb_bfm.apb_write(8'h08, tx_data_arr[i]);
            ref_model.apb_write(8'h08, tx_data_arr[i]);
            coverage.sample_fifo(ref_model.tx_fifo.size(), ref_model.rx_fifo.size());
        end

        // Read STATUS and compare (Verifies TX_FULL)
        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        // ---------------------------------------------------------------------
        // STEP 2: Trigger TX_OVF by pushing a 9th item
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Triggering TX_OVF");
        tx_ovf_val = $urandom();
        tb_top.u_apb_bfm.apb_write(8'h08, tx_ovf_val);
        ref_model.apb_write(8'h08, tx_ovf_val);

        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        // ---------------------------------------------------------------------
        // STEP 3: Wait for all 8 items to transfer to RX FIFO
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Waiting for 8 transfers to complete");
        for (int i = 0; i < 8; i++) begin
            ref_model.predict_transfer(tx_data_arr[i], 32'h0, rand_txn.loopback, rand_txn.width, rand_txn.lsb_first);
            ref_model.mark_transfer_start();
            
            // Wait for TRANSFER_DONE
            do begin
                spi_sequence_lib::apb_read_sync(8'h1C, int_stat_val);
            end while (int_stat_val[4] == 1'b0);

            // Clear TRANSFER_DONE
            tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_0010);
            ref_model.mark_transfer_done(32'h0);
            ref_model.apb_write(8'h1C, 32'h0000_0010);
            
            coverage.sample_fifo(ref_model.tx_fifo.size(), ref_model.rx_fifo.size());
        end

        // Verify RX_FULL after 8 transfers
        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        // ---------------------------------------------------------------------
        // STEP 4: Trigger RX_OVF by pushing 1 more item while RX is full
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Triggering RX_OVF");
        rx_ovf_val = $urandom();
        tb_top.u_apb_bfm.apb_write(8'h08, rx_ovf_val);
        ref_model.apb_write(8'h08, rx_ovf_val);
        
        ref_model.predict_transfer(rx_ovf_val, 32'h0, rand_txn.loopback, rand_txn.width, rand_txn.lsb_first);
        ref_model.mark_transfer_start();
        
        do begin
            spi_sequence_lib::apb_read_sync(8'h1C, int_stat_val);
        end while (int_stat_val[4] == 1'b0);
        
        tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_0010);
        ref_model.mark_transfer_done(32'h0);
        ref_model.apb_write(8'h1C, 32'h0000_0010);

        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        // ---------------------------------------------------------------------
        // STEP 5: Drain RX FIFO and verify data integrity
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Draining RX FIFO");
        for (int i = 0; i < 8; i++) begin
            spi_sequence_lib::apb_read_sync(8'h0C, rx_word);
            ref_model.check_rx(rx_word); 
            coverage.sample_fifo(ref_model.tx_fifo.size(), ref_model.rx_fifo.size());
        end

        // Read STATUS to ensure empty
        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        spi_sequence_lib::target_ss(4'b0000);

        $display("[INFO] fifo_stress_test: finished, errors=%0d", ref_model.error_count);
    endtask
endclass

`endif // FIFO_STRESS_TEST_SV
