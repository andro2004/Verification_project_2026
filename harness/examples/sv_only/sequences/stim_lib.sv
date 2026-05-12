// =============================================================================
// stim_lib.sv
// -----------------------------------------------------------------------------
// Reusable randomisable transaction classes and sequence library.
// =============================================================================

`ifndef SPI_STIM_LIB_SV
`define SPI_STIM_LIB_SV

// ---------------------------------------------------------------------------
// Register address aliases (mirror apb_master_bfm.sv)
// ---------------------------------------------------------------------------
localparam [7:0] SL_CTRL     = 8'h00;
localparam [7:0] SL_STATUS   = 8'h04;
localparam [7:0] SL_TX_DATA  = 8'h08;
localparam [7:0] SL_RX_DATA  = 8'h0C;
localparam [7:0] SL_CLK_DIV  = 8'h10;
localparam [7:0] SL_SS_CTRL  = 8'h14;
localparam [7:0] SL_INT_EN   = 8'h18;
localparam [7:0] SL_INT_STAT = 8'h1C;
localparam [7:0] SL_DELAY    = 8'h20;

localparam int SL_STATUS_BUSY     = 0;
localparam int SL_STATUS_TX_FULL  = 1;
localparam int SL_STATUS_TX_EMPTY = 2;
localparam int SL_STATUS_RX_FULL  = 3;
localparam int SL_STATUS_RX_EMPTY = 4;
localparam int SL_STATUS_TX_OVF   = 5;
localparam int SL_STATUS_RX_OVF   = 6;

localparam int SL_POLL_TIMEOUT = 5000;

class spi_txn;
    rand bit [1:0]  mode;
    rand bit        lsb_first;
    rand bit [1:0]  width;
    rand bit [15:0] clk_div;
    rand bit [7:0]  delay_cfg;
    rand bit [31:0] tx_data;
    rand bit        loopback;
    rand bit [3:0]  ss_en;

    constraint c_width_legal  { width inside {2'b00, 2'b01, 2'b10}; }
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd15]}; }
    constraint c_delay_sane   { delay_cfg inside {[8'd0 : 8'd7]}; }
    constraint c_ss_active    { ss_en != 4'b0000; }

    function bit [31:0] pack_ctrl_word();
        return { 24'b0, width, loopback, lsb_first, mode, 1'b1, 1'b1 };
    endfunction

    function bit [31:0] pack_ss_ctrl_word();
        return {24'b0, 4'b0000, ss_en};
    endfunction

    function int transfer_bits();
        case (width)
            2'b00:   return 8;
            2'b01:   return 16;
            default: return 32;
        endcase
    endfunction

    // ---- Debug sprint -------------------------------------------------------
    function string sprint();
        return $sformatf(
            "mode=%0d lsb=%0b width=%0d div=%0d delay=%0d tx=0x%08h lb=%0b ss_en=0x%h",
            mode, lsb_first, transfer_bits(), clk_div, delay_cfg, tx_data, loopback, ss_en);
    endfunction
endclass

class spi_txn_clkdiv_corner extends spi_txn;
    constraint c_clk_div_sane {
        clk_div inside { 16'd0, 16'd1, 16'd2, 16'd3, 16'd255, 16'd1024, 16'd65535 };
    }
endclass

class spi_txn_fifo extends spi_txn;
    rand int unsigned burst_len;
    constraint c_burst_len { burst_len inside {[1:8]}; }
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd3]}; }
endclass

class spi_txn_delay extends spi_txn;
    constraint c_delay_sane { delay_cfg inside {8'd0, 8'd1, [8'd128 : 8'd255]}; }
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd3]}; }
endclass

class spi_sequence_lib;

    static task configure_dut(spi_txn txn);
        tb_top.u_apb_bfm.apb_write(SL_CLK_DIV, {16'b0, txn.clk_div});
        tb_top.u_ref.apb_write(SL_CLK_DIV, {16'b0, txn.clk_div});

        tb_top.u_apb_bfm.apb_write(SL_DELAY, {24'b0, txn.delay_cfg});
        tb_top.u_ref.apb_write(SL_DELAY, {24'b0, txn.delay_cfg});

        tb_top.u_apb_bfm.apb_write(SL_INT_EN, 32'h0000_001F);
        tb_top.u_ref.apb_write(SL_INT_EN, 32'h0000_001F);

        tb_top.u_apb_bfm.apb_write(SL_CTRL, txn.pack_ctrl_word());
        tb_top.u_ref.apb_write(SL_CTRL, txn.pack_ctrl_word());
    endtask

    static task target_ss(bit [3:0] ss_en_bits);
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, {24'b0, 4'b0000, ss_en_bits});
        tb_top.u_ref.apb_write(SL_SS_CTRL, {24'b0, 4'b0000, ss_en_bits});
    endtask

    static task push_single(spi_txn txn);
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
        tb_top.u_ref.apb_write(SL_TX_DATA, txn.tx_data);
    endtask

    static task push_burst(spi_txn txn_q[$]);
        foreach (txn_q[i]) begin
            tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn_q[i].tx_data);
            tb_top.u_ref.apb_write(SL_TX_DATA, txn_q[i].tx_data);
        end
    endtask

    static task apb_read_sync(input bit [7:0] addr, output bit [31:0] data);
        tb_top.u_apb_bfm.apb_read(addr, data);
        // Cast to void to fix the vlog-2240 implicit cast warning
        void'(tb_top.u_ref.apb_read(addr));
    endtask

    static task pop_rx_burst(output bit [31:0] rx_q[$]);
        bit [31:0] status, rdata;
        rx_q = {};
        
        apb_read_sync(SL_STATUS, status);
        while (!status[SL_STATUS_RX_EMPTY]) begin
            apb_read_sync(SL_RX_DATA, rdata);
            rx_q.push_back(rdata);
            apb_read_sync(SL_STATUS, status);
        end
    endtask

    static task wait_idle();
        bit [31:0] status;
        int cycles = 0;

        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        while (status[SL_STATUS_BUSY]) begin
            if (cycles >= SL_POLL_TIMEOUT) begin
                $display("[CHECKER_ERROR] wait_idle: DUT hung?");
                return;
            end
            tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
            cycles++;
        end
    endtask

    static task read_status(output bit [31:0] status);
        apb_read_sync(SL_STATUS, status);
    endtask

    static task clear_interrupts(output bit [31:0] int_stat_before);
        tb_top.u_apb_bfm.apb_read (SL_INT_STAT, int_stat_before);
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT, int_stat_before);
        tb_top.u_ref.apb_write(SL_INT_STAT, int_stat_before);
    endtask

    static task inject_error(input bit [7:0] addr, input bit [31:0] data, output bit [31:0] readback);
        tb_top.u_apb_bfm.apb_write(addr, data);
        tb_top.u_apb_bfm.apb_read (addr, readback);
    endtask

    // =========================================================================
    // do_transfer
    // =========================================================================
    static task do_transfer(spi_txn txn, output bit [31:0] rx_word);
        configure_dut(txn);
        push_single(txn);
        target_ss(txn.ss_en);
        wait_idle();
        target_ss(4'b0000);
        apb_read_sync(SL_RX_DATA, rx_word);
    endtask

    // =========================================================================
    // do_burst_transfer
    // =========================================================================
    static task do_burst_transfer(spi_txn txn_q[$], output bit [31:0] rx_q[$]);
        if (txn_q.size() == 0) return;

        configure_dut(txn_q[0]);
        push_burst(txn_q);
        target_ss(txn_q[0].ss_en);
        wait_idle();
        target_ss(4'b0000);
        pop_rx_burst(rx_q); 
    endtask

    static task reset_dut();
        tb_top.u_apb_bfm.apb_write(SL_CTRL,    32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0000); 
        tb_top.u_apb_bfm.apb_write(SL_INT_EN,  32'h0000_0000); 
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT,32'h0000_001F);
        
        tb_top.u_ref.apb_write(SL_CTRL,    32'h0000_0000);
        tb_top.u_ref.apb_write(SL_SS_CTRL, 32'h0000_0000);
        tb_top.u_ref.apb_write(SL_INT_EN,  32'h0000_0000);
        tb_top.u_ref.apb_write(SL_INT_STAT,32'h0000_001F);
    endtask

endclass

`endif // SPI_STIM_LIB_SV
