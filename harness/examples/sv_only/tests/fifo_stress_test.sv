// =============================================================================
// fifo_stress_test.sv  (Owner: M3)
// -----------------------------------------------------------------------------
// Purpose: Stress the TX/RX FIFOs. Push 8 entries to fill TX, let them transfer
// to fill RX, overflow both, verify flags (empty, full, overflow), and ensure
// data integrity across the FIFOs.
// =============================================================================

`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"

class fifo_stress_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [31:0] rx_word, status_val, int_stat_val;
        spi_txn txn;

        $display("[INFO] fifo_stress_test: starting");

        spi_sequence_lib::reset_dut();
        ref_model.reset();

        // ---------------------------------------------------------------------
        // STEP 0: Configuration
        // ---------------------------------------------------------------------
        txn = new();
        txn.mode       = 2'b00;
        txn.width      = 2'b00; // 8-bit
        txn.lsb_first  = 1'b0;
        txn.loopback   = 1'b1;  // Loopback to reliably check data integrity
        txn.clk_div    = 16'd4;
        txn.delay_cfg  = 8'd0;
        txn.ss_en      = 4'b0001;

        spi_sequence_lib::configure_dut(txn);
        spi_sequence_lib::target_ss(txn.ss_en);

        // ---------------------------------------------------------------------
        // STEP 1: Fill TX FIFO to capacity (8 items) & Verify TX_FULL
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Filling TX FIFO with 8 items");
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_write(8'h08, 32'h10 + i);
            ref_model.apb_write(8'h08, 32'h10 + i);
            coverage.sample_fifo(ref_model.tx_fifo.size(), ref_model.rx_fifo.size());
        end

<<<<<<< Updated upstream
        // Read STATUS and compare (Verifies TX_FULL)
        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);
=======
        // Mandatory contract check utilizing the explicit wrapper hierarchy path (Section 7)
        if (tb_top.u_wrap.u_dut.u_regfile.tx_full_w !== 1'b1) begin
            $display("[CHECKER_ERROR] TX_FULL failed to assert after 8 writes!");
            error_count++;
        end
>>>>>>> Stashed changes

        // ---------------------------------------------------------------------
        // STEP 2: Trigger TX_OVF by pushing a 9th item
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Triggering TX_OVF");
        tb_top.u_apb_bfm.apb_write(8'h08, 32'hFF);
        ref_model.apb_write(8'h08, 32'hFF);

        spi_sequence_lib::apb_read_sync(8'h04, status_val);
        ref_model.check_status(status_val);

        // ---------------------------------------------------------------------
        // STEP 3: Wait for all 8 items to transfer to RX FIFO
        // ---------------------------------------------------------------------
        $display("[INFO] fifo_stress_test: Waiting for 8 transfers to complete");
        for (int i = 0; i < 8; i++) begin
            ref_model.predict_transfer(32'h10 + i, 32'h0, 1'b1, 2'b00, 1'b0); // Loopback
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
        tb_top.u_apb_bfm.apb_write(8'h08, 32'hEE);
        ref_model.apb_write(8'h08, 32'hEE);
        
        ref_model.predict_transfer(32'hEE, 32'h0, 1'b1, 2'b00, 1'b0);
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
