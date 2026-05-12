// =============================================================================
// tb_top.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Plain-SV top-level module. Instantiates the DUT wrapper, the APB master BFM,
// the SPI slave BFM, the scoreboard/coverage collectors, and selects the test
// via +TESTNAME=<name> (or +UVM_TESTNAME=<name> as a fallback so the same
// Makefile works for SV-only and UVM flows).
//
// Contract with the grader:
//   * Every test MUST end with exactly one "[TEST_PASSED] <name>" or
//     "[TEST_FAILED] <name> errors=<n>" line. The stub below satisfies that
//     for the sanity_test example.
// =============================================================================

`timescale 1ns/1ps
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
`include "../sequences/stim_lib.sv"
`include "../tests/sanity_test.sv"
`include "../tests/randomized_sanity_test.sv"
`include "../tests/loopback_test.sv"
`include "../tests/error_injection_test.sv"
`include "../tests/reg_access_test.sv"
`include "../tests/mode_coverage_test.sv"
`include "../tests/width_coverage_test.sv"
`include "../tests/delay_transfer_test.sv"
`include "../tests/clk_div_corner_test.sv"
`include "../tests/interrupt_test.sv"
`include "../tests/fifo_stress_test.sv"
`include "../tests/coverage_smoke_test.sv"

module tb_top;

    // ----------------- Clock and reset --------------------------------------
    bit PCLK = 0;
    always #5 PCLK = ~PCLK;   // 100 MHz

    bit PRESETn;

    // ----------------- Interfaces -------------------------------------------
    apb_if apb (.pclk(PCLK), .presetn(PRESETn));
    spi_if spi (.pclk(PCLK));

    // Local signals used only by the slave BFM
    logic [1:0] bfm_mode    = 2'b00;
    logic [7:0] bfm_pattern = 8'hA5;

    // ----------------- DUT wrapper -----------------------------------------
    dut_wrapper u_wrap (.apb(apb), .spi(spi));

    // ----------------- BFMs -------------------------------------------------
    apb_master_bfm u_apb_bfm (.apb(apb.master));
    spi_slave_bfm  u_spi_bfm (.spi(spi.slave), .mode(bfm_mode),
                              .miso_data(bfm_pattern));

    // ----------------- Predictor / Scoreboard / Coverage --------------------
    spi_ref_model    u_ref   = new();
    spi_coverage_col u_cov   = new();

    // ----------------- SVA bind ---------------------------------------------
    // Bind by *instance path* relative to tb_top: u_wrap is the dut_wrapper
    // instance, u_dut is the spi_master instance inside it, u_regfile is the
    // apb_regfile instance inside spi_master. The bind injects spi_sva into
    // the u_regfile instance with port hookups read from the same scope.
    // ModelSim requires complex expressions to be assigned to wires before binding
    wire [3:0] bind_tx_ptr = u_wrap.u_dut.u_regfile.tx_wp - u_wrap.u_dut.u_regfile.tx_rp;
    wire [3:0] bind_rx_ptr = u_wrap.u_dut.u_regfile.rx_wp - u_wrap.u_dut.u_regfile.rx_rp;
    
    wire [4:0] bind_hw_event = {
        u_wrap.u_dut.u_regfile.transfer_done_pulse,                                                               // transfer done bit 
        (u_wrap.u_dut.u_regfile.rx_push_valid && u_wrap.u_dut.u_regfile.rx_full_w),                               // rx_ovf
        u_wrap.u_dut.u_regfile.tx_push_dropped,                                                                   // tx_ovf 
        (u_wrap.u_dut.u_regfile.rx_push_valid && !u_wrap.u_dut.u_regfile.rx_full_w && (u_wrap.u_dut.u_regfile.rx_count == 7)), // rx_full
        (u_wrap.u_dut.u_regfile.tx_pop && (u_wrap.u_dut.u_regfile.tx_count == 1))                                 // tx_empty
    };

    wire [5:0] bind_width = (u_wrap.u_dut.u_core.xfer_width == 2'b00) ? 6'd8 : 
                            (u_wrap.u_dut.u_core.xfer_width == 2'b01) ? 6'd16 : 6'd32;

    // Pulling the bit-select out into a wire to satisfy ModelSim's strict binding rules
    wire bind_ovf = u_wrap.u_dut.u_regfile.int_stat[2];

    bind u_wrap.u_dut.u_regfile spi_sva u_sva (
        .PCLK   (PCLK),
        .PRESETn(PRESETn),
        .PSEL   (apb.psel),
        .PENABLE(apb.penable),
        .PREADY (apb.pready),
        .PSLVERR(apb.pslverr),
        .PADDR  (apb.paddr),
        .PWRITE (apb.pwrite),
        .PWDATA (apb.pwdata),
        .ctrl_en(u_wrap.u_dut.u_regfile.ctrl_en),
        .int_stat(u_wrap.u_dut.u_regfile.int_stat),
        .int_en  (u_wrap.u_dut.u_regfile.int_en),
        .IRQ     (u_wrap.u_dut.u_regfile.IRQ),
        .FULL    (u_wrap.u_dut.u_regfile.tx_full_w),
        .OVF     (bind_ovf), // <--- Used the new wire here
        .push    (u_wrap.u_dut.u_regfile.tx_push_valid),
        .tx_ptr  (bind_tx_ptr),
        .rx_ptr  (bind_rx_ptr),
        .hw_event(bind_hw_event),
        .sclk    (u_wrap.u_dut.u_core.SCLK),
        .mosi    (u_wrap.u_dut.u_core.MOSI),
        .cpol    (u_wrap.u_dut.u_core.cpol),
        .cpha    (u_wrap.u_dut.u_core.cpha),
        .ss_n    (u_wrap.u_dut.u_regfile.SS_n),
        .sclk_cnt(u_wrap.u_dut.u_core.sclk_cnt),
        .sclk_phase(u_wrap.u_dut.u_core.sclk_phase),
        .cfg_clk_div(u_wrap.u_dut.u_core.cfg_clk_div),
        .BUSY    (u_wrap.u_dut.u_core.busy),
        .width   (bind_width)
    );

    // ----------------- Test dispatch ----------------------------------------
    string testname;

    initial begin
        PRESETn = 0;
        #50;
        PRESETn = 1;

        if (!$value$plusargs("TESTNAME=%s", testname) &&
            !$value$plusargs("UVM_TESTNAME=%s", testname))
            testname = "sanity_test";

        $display("[INFO] Starting test: %s", testname);

       case (testname)

    "sanity_test"            : sanity_test::run(u_ref, u_cov);

    "randomized_sanity_test" : randomized_sanity_test::run(u_ref, u_cov);

    "coverage_smoke_test"    : coverage_smoke_test::run(u_ref, u_cov);

    "ral_hw_reset_test" : begin
        $display("[TEST_SKIPPED] ral_hw_reset_test");
        $finish;
    end

    default : begin
        $display("[TEST_FAILED] %s errors=1 (unknown test name)", testname);
        $finish;
    end

endcase
        // Single PASS line for the dispatcher. Each test::run task is
        // expected to have printed [SCOREBOARD_ERROR] on mismatches and
        // incremented u_ref.error_count; convert that into the final
        // PASS/FAIL line here.
        if (u_ref.error_count == 0)
            $display("[TEST_PASSED] %s", testname);
        else
            $display("[TEST_FAILED] %s errors=%0d", testname, u_ref.error_count);
        $finish;
    end

    // ----------------- Safety timeout ---------------------------------------
    initial begin
        #10_000_000;  // 10 ms worth of sim time
        $display("[TEST_FAILED] %s errors=1  (timeout)", testname);
        $finish;
    end

endmodule
