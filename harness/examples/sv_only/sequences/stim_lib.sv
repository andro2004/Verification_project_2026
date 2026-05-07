// =============================================================================
// stim_lib.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Reusable randomisable transaction classes. Tests `new` these, call
// `randomize()`, and drive the resulting fields through the APB master BFM.
//
// NOTE: The scaffold only defines a single spi_txn class; students should
// add per-test variants as their coverage goals require.
// =============================================================================

`ifndef SPI_STIM_LIB_SV
`define SPI_STIM_LIB_SV

class spi_txn;
    rand bit [1:0]  mode;       // {CPOL, CPHA}
    rand bit        lsb_first;
    rand bit [1:0]  width;      // 00=8, 01=16, 10=32
    rand bit [15:0] clk_div;
    rand bit [7:0]  delay_cfg;
    rand bit [31:0] tx_data;
    rand bit        loopback;

    constraint c_width_legal  { width inside {[0:2]}; }
    constraint c_clk_div_sane { clk_div inside {[0:2048]}; }
    constraint c_delay_sane   { delay_cfg inside {[0:31]}; }

    function string sprint();
        return $sformatf("mode=%0d lsb=%0b width=%0d div=%0d delay=%0d tx=0x%08h lb=%0b",
                         mode, lsb_first, width, clk_div, delay_cfg, tx_data, loopback);
    endfunction

    // TODO: Implement pack_ctrl_word()
    // It must take the randomized class variables (mode, width, lsb_first, loopback) 
    // and pack them into a 32-bit vector for the hardware CTRL register (with EN and MSTR set to 1).
    function bit [31:0] pack_ctrl_word();
        return 32'h0; // Replace with actual implementation
    endfunction
endclass

class spi_sequence_lib;

    // TODO: Implement configure_dut
    // Write to CLK_DIV, DELAY, INT_EN, and CTRL.
    static task configure_dut(spi_txn txn);
    endtask

    // TODO: Implement target_ss
    // Assert/de-assert Slave Select lanes via SS_CTRL.
    static task target_ss(bit [3:0] ss_ctrl);
    endtask

    // TODO: Implement push_single
    // Task for a single-word push to TX_DATA.
    static task push_single(spi_txn txn);
    endtask

    // TODO: Implement push_burst
    // Task for burst pushes to TX_DATA.
    static task push_burst(spi_txn txn_q[$]);
    endtask

    // TODO: Implement pop_rx_burst
    // Poll STATUS and harvest data from RX_DATA into an output queue.
    static task pop_rx_burst(output bit [31:0] rx_q[$]);
    endtask

    // TODO: Implement wait_idle
    // Wait for BUSY to clear.
    static task wait_idle();
    endtask

    // TODO: Implement clear_interrupts
    // Task to read INT_STAT and write-1-clear it.
    static task clear_interrupts(output bit [31:0] int_stat);
    endtask

    // TODO: Implement inject_error
    // Write arbitrary data to reserved register offsets.
    static task inject_error(bit [7:0] addr, bit [31:0] data);
    endtask

endclass

`endif // SPI_STIM_LIB_SV
