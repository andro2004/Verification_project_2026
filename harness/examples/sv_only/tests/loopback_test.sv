// loopback_test.sv — STUB (Owner: M6)
// Purpose: LOOPBACK=1, MISO=nonsense, verify RX==TX (R19)
`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
class loopback_test;

    static const bit [7:0] LB_CTRL     = 8'h00;
    static const bit [7:0] LB_STATUS   = 8'h04;
    static const bit [7:0] LB_TX_DATA  = 8'h08;
    static const bit [7:0] LB_RX_DATA  = 8'h0C;
    static const bit [7:0] LB_CLK_DIV  = 8'h10;
    static const bit [7:0] LB_SS_CTRL  = 8'h14;
    static const bit [7:0] LB_INT_EN   = 8'h18;
    static const bit [7:0] LB_INT_STAT = 8'h1C;
    static const bit [7:0] LB_DELAY    = 8'h20;

    // ============================================================
    // perform a single loopback transfer and check RX == TX
    // ============================================================
    static task do_loopback_xfer(
        ref spi_ref_model     ref_model,
        ref spi_coverage_col  coverage,
        input bit [1:0]  mode,
        input bit [1:0]  width,
        input bit        lsb_first,
        input bit [31:0] tx_data,
        input bit [31:0] miso_nonsense,  // driven on MISO — must be ignored
        input bit [15:0] clk_div
    );
        bit [31:0] ctrl_word;
        bit [31:0] rd;
        bit [31:0] expected_rx;
        int        xfer_bits;
        bit [31:0] tx_masked;
        // Compute the width-masked TX value (this is what RX should equal)
        case (width)
            2'b00: begin tx_masked = tx_data & 32'h0000_00FF; xfer_bits = 8;  end
            2'b01: begin tx_masked = tx_data & 32'h0000_FFFF; xfer_bits = 16; end
            default: begin tx_masked = tx_data;                xfer_bits = 32; end
        endcase
        expected_rx = tx_masked;
        // Configure the slave BFM to drive nonsense on MISO
        tb_top.bfm_mode      = mode;
        tb_top.bfm_pattern   = miso_nonsense;
        tb_top.bfm_lsb_first = lsb_first;
        tb_top.bfm_width     = width;
        // Build CTRL word: {width[7:6], loopback[5], lsb_first[4], mode[3:2], MSTR[1], EN[0]}
        ctrl_word = {24'b0, width, 1'b1, lsb_first, mode, 1'b1, 1'b1};
        //                          ^loopback=1              ^MSTR ^EN
        // Disable first to flush (R3)
        tb_top.u_apb_bfm.apb_write(LB_CTRL, 32'h0000_0000);
        ref_model.apb_write(32'h00, 32'h0000_0000);
        // Configure
        tb_top.u_apb_bfm.apb_write(LB_CLK_DIV, {16'b0, clk_div});
        ref_model.apb_write(32'h10, {16'b0, clk_div});
        tb_top.u_apb_bfm.apb_write(LB_INT_EN, 32'h0000_001F);
        ref_model.apb_write(32'h18, 32'h0000_001F);
        tb_top.u_apb_bfm.apb_write(LB_CTRL, ctrl_word);
        ref_model.apb_write(32'h00, ctrl_word);
        // Sample config coverage
        coverage.sample_config(.mode(mode), .lsb_first(lsb_first),
                               .width(width), .loopback(1'b1));
        coverage.sample_register(LB_CTRL, 1'b1);
        // Predict the transfer in the ref model
        ref_model.predict_transfer(
            .tx_data(tx_data),
            .miso_pattern(miso_nonsense),
            .loopback(1'b1),
            .width(width),
            .lsb_first(lsb_first)
        );
        // Push TX data
        tb_top.u_apb_bfm.apb_write(LB_TX_DATA, tx_data);
        ref_model.apb_write(32'h08, tx_data);
        coverage.sample_register(LB_TX_DATA, 1'b1);
        // Assert SS to start transfer
        tb_top.u_apb_bfm.apb_write(LB_SS_CTRL, 32'h0000_0001);
        ref_model.apb_write(32'h14, 32'h0000_0001);
        coverage.sample_ss(4'b0001);
        coverage.sample_register(LB_SS_CTRL, 1'b1);
        // Wait for transfer to complete (poll BUSY)
        repeat (5000) begin
            tb_top.u_apb_bfm.apb_read(LB_STATUS, rd);
            if (rd[0] == 1'b0) break;
        end
        // De-assert SS
        tb_top.u_apb_bfm.apb_write(LB_SS_CTRL, 32'h0000_0000);
        ref_model.apb_write(32'h14, 32'h0000_0000);
        // Read RX_DATA
        tb_top.u_apb_bfm.apb_read(LB_RX_DATA, rd);
        void'(ref_model.apb_read(32'h0C));
        coverage.sample_register(LB_RX_DATA, 1'b0);
        // Scoreboard check: in loopback, RX must equal the masked TX data
        ref_model.check_rx(rd);
        // Additional explicit check for clarity in the log
        if (rd !== expected_rx) begin
            $display("[SCOREBOARD_ERROR] loopback_test: mode=%0d width=%0d lsb=%0b TX=0x%08h expected_RX=0x%08h actual_RX=0x%08h (MISO_nonsense=0x%08h)",
                     mode, xfer_bits, lsb_first, tx_data, expected_rx, rd, miso_nonsense);
        end else begin
            $display("[INFO] loopback_test: PASS mode=%0d width=%0d lsb=%0b TX=0x%08h RX=0x%08h",
                     mode, xfer_bits, lsb_first, tx_data, rd);
        end
    endtask

    // ============================================================
    // Main test body
    // ============================================================
    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        $display("[INFO] loopback_test: starting");
        
        $display("[INFO] loopback_test: Test 1 — Basic 8-bit loopback (mode 0)");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b00), .lsb_first(1'b0),
            .tx_data(32'h0000_005A),
            .miso_nonsense(32'h0000_00FF),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 2 — 8-bit with different pattern");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b00), .lsb_first(1'b0),
            .tx_data(32'h0000_00C3),
            .miso_nonsense(32'h0000_0055),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 3 — 16-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b01), .lsb_first(1'b0),
            .tx_data(32'h0000_ABCD),
            .miso_nonsense(32'h0000_1234),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 4 — 32-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b10), .lsb_first(1'b0),
            .tx_data(32'hDEAD_BEEF),
            .miso_nonsense(32'h1234_5678),
            .clk_div(16'd2)
        );
        
        $display("[INFO] loopback_test: Test 5 — Mode 1, 8-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b01), .width(2'b00), .lsb_first(1'b0),
            .tx_data(32'h0000_0077),
            .miso_nonsense(32'h0000_00AA),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 6 — Mode 2, 8-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b10), .width(2'b00), .lsb_first(1'b0),
            .tx_data(32'h0000_0033),
            .miso_nonsense(32'h0000_00CC),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 7 — Mode 3, 8-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b11), .width(2'b00), .lsb_first(1'b0),
            .tx_data(32'h0000_00E1),
            .miso_nonsense(32'h0000_001E),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 8 — LSB-first 8-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b00), .lsb_first(1'b1),
            .tx_data(32'h0000_00B4),
            .miso_nonsense(32'h0000_004B),
            .clk_div(16'd4)
        );
        
        $display("[INFO] loopback_test: Test 9 — LSB-first 16-bit loopback");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b00), .width(2'b01), .lsb_first(1'b1),
            .tx_data(32'h0000_9876),
            .miso_nonsense(32'h0000_6789),
            .clk_div(16'd3)
        );
        
        $display("[INFO] loopback_test: Test 10 — Mode 3, 32-bit, LSB-first");
        do_loopback_xfer(ref_model, coverage,
            .mode(2'b11), .width(2'b10), .lsb_first(1'b1),
            .tx_data(32'hCAFE_BABE),
            .miso_nonsense(32'hFFFF_FFFF),
            .clk_div(16'd2)
        );
        
        tb_top.u_apb_bfm.apb_write(LB_CTRL,    32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(LB_SS_CTRL, 32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(LB_INT_EN,  32'h0000_0000);
        ref_model.apb_write(32'h00, 32'h0000_0000);
        ref_model.apb_write(32'h14, 32'h0000_0000);
        ref_model.apb_write(32'h18, 32'h0000_0000);
        $display("[INFO] loopback_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask
endclass
`endif // LOOPBACK_TEST_SV
