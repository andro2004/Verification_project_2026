// reg_access_test.sv — STUB (Owner: M5)
// Purpose: Reset values + write-read for every R/W register (R1, R2)
`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
class reg_access_test;
    static const bit [7:0] CTRL     = 8'h00;
    static const bit [7:0] STATUS   = 8'h04;
    static const bit [7:0] TX_DATA  = 8'h08;
    static const bit [7:0] RX_DATA  = 8'h0C;
    static const bit [7:0] CLK_DIV  = 8'h10;
    static const bit [7:0] SS_CTRL  = 8'h14;
    static const bit [7:0] INT_EN   = 8'h18;
    static const bit [7:0] INT_STAT = 8'h1C;
    static const bit [7:0] DELAY    = 8'h20;

    // ==========================================================
    // APB write with ref-model sync + coverage sampling
    // ==========================================================
    static task apb_wr(ref spi_ref_model ref_model,
                       ref spi_coverage_col coverage,
                       input bit [7:0] addr, input bit [31:0] data);
        tb_top.u_apb_bfm.apb_write(addr, data);
        ref_model.apb_write({24'h0, addr}, data);
        coverage.sample_register(addr, 1'b1);
    endtask

    // ==========================================================
    // APB read with ref-model sync + coverage sampling
    // ==========================================================
    static task apb_rd(ref spi_ref_model ref_model,
                       ref spi_coverage_col coverage,
                       input bit [7:0] addr, output bit [31:0] data);
        tb_top.u_apb_bfm.apb_read(addr, data);
        void'(ref_model.apb_read({24'h0, addr}));
        coverage.sample_register(addr, 1'b0);
    endtask

    // ==========================================================
    // Check a register value against an expected value
    // ==========================================================
    static task check(ref spi_ref_model ref_model,
                      input string name,
                      input bit [31:0] expected,
                      input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] reg_access_test %s: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            ref_model.error_count++;
        end else begin
            $display("[INFO] reg_access_test %s: OK (0x%08h)", name, observed);
        end
    endtask

    // ===========================================================
    // Main test body
    // ===========================================================
    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        bit [31:0] rd;
        $display("[INFO] reg_access_test: starting");
        
        $display("[INFO] reg_access_test: Phase 1 — Reset value checks");
        apb_rd(ref_model, coverage, CTRL, rd);
        check(ref_model, "CTRL reset", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, STATUS, rd);
        // STATUS after reset: BUSY=0, TX_FULL=0, TX_EMPTY=1(bit2), RX_FULL=0,
        //                     RX_EMPTY=1(bit4), TX_OVF=0, RX_OVF=0
        check(ref_model, "STATUS reset", 32'h0000_0014, rd);
        apb_rd(ref_model, coverage, TX_DATA, rd);
        check(ref_model, "TX_DATA reset (WO read)", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, RX_DATA, rd);
        check(ref_model, "RX_DATA reset (empty)", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, CLK_DIV, rd);
        check(ref_model, "CLK_DIV reset", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, SS_CTRL, rd);
        check(ref_model, "SS_CTRL reset", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, INT_EN, rd);
        check(ref_model, "INT_EN reset", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, INT_STAT, rd);
        check(ref_model, "INT_STAT reset", 32'h0000_0000, rd);
        apb_rd(ref_model, coverage, DELAY, rd);
        check(ref_model, "DELAY reset", 32'h0000_0000, rd);
        
        $display("[INFO] reg_access_test: Phase 2 — Write-then-readback");
        // --- CTRL (0x00) --- Bits [7:0] are writable, [31:8] reserved
        // Write all 1s, expect only bits [7:0] = 0xFF
        apb_wr(ref_model, coverage, CTRL, 32'hFFFF_FFFF);
        apb_rd(ref_model, coverage, CTRL, rd);
        check(ref_model, "CTRL write 0xFF", 32'h0000_00FF, rd);
        // Write a specific pattern
        apb_wr(ref_model, coverage, CTRL, 32'h0000_00A5);
        apb_rd(ref_model, coverage, CTRL, rd);
        check(ref_model, "CTRL write 0xA5", 32'h0000_00A5, rd);
        // Write 0 to disable EN (this also flushes FIFOs per R3)
        apb_wr(ref_model, coverage, CTRL, 32'h0000_0000);
        apb_rd(ref_model, coverage, CTRL, rd);
        check(ref_model, "CTRL write 0x00", 32'h0000_0000, rd);
        // --- CLK_DIV (0x10) --- Bits [15:0] writable, [31:16] reserved
        apb_wr(ref_model, coverage, CLK_DIV, 32'hFFFF_FFFF);
        apb_rd(ref_model, coverage, CLK_DIV, rd);
        check(ref_model, "CLK_DIV write 0xFFFF", 32'h0000_FFFF, rd);
        apb_wr(ref_model, coverage, CLK_DIV, 32'h0000_1234);
        apb_rd(ref_model, coverage, CLK_DIV, rd);
        check(ref_model, "CLK_DIV write 0x1234", 32'h0000_1234, rd);
        apb_wr(ref_model, coverage, CLK_DIV, 32'h0000_0000);
        apb_rd(ref_model, coverage, CLK_DIV, rd);
        check(ref_model, "CLK_DIV write 0x0000", 32'h0000_0000, rd);
        // --- SS_CTRL (0x14) --- Bits [7:0] writable (ss_en[3:0], ss_val[3:0])
        apb_wr(ref_model, coverage, SS_CTRL, 32'hFFFF_FFFF);
        apb_rd(ref_model, coverage, SS_CTRL, rd);
        check(ref_model, "SS_CTRL write 0xFF", 32'h0000_00FF, rd);
        apb_wr(ref_model, coverage, SS_CTRL, 32'h0000_005A);
        apb_rd(ref_model, coverage, SS_CTRL, rd);
        check(ref_model, "SS_CTRL write 0x5A", 32'h0000_005A, rd);
        apb_wr(ref_model, coverage, SS_CTRL, 32'h0000_0000);
        apb_rd(ref_model, coverage, SS_CTRL, rd);
        check(ref_model, "SS_CTRL write 0x00", 32'h0000_0000, rd);
        // --- INT_EN (0x18) --- Bits [4:0] writable, [31:5] reserved
        apb_wr(ref_model, coverage, INT_EN, 32'hFFFF_FFFF);
        apb_rd(ref_model, coverage, INT_EN, rd);
        check(ref_model, "INT_EN write 0x1F", 32'h0000_001F, rd);
        apb_wr(ref_model, coverage, INT_EN, 32'h0000_0015);
        apb_rd(ref_model, coverage, INT_EN, rd);
        check(ref_model, "INT_EN write 0x15", 32'h0000_0015, rd);
        apb_wr(ref_model, coverage, INT_EN, 32'h0000_0000);
        apb_rd(ref_model, coverage, INT_EN, rd);
        check(ref_model, "INT_EN write 0x00", 32'h0000_0000, rd);
        // --- DELAY (0x20) --- Bits [7:0] writable, [31:8] reserved
        apb_wr(ref_model, coverage, DELAY, 32'hFFFF_FFFF);
        apb_rd(ref_model, coverage, DELAY, rd);
        check(ref_model, "DELAY write 0xFF", 32'h0000_00FF, rd);
        apb_wr(ref_model, coverage, DELAY, 32'h0000_007B);
        apb_rd(ref_model, coverage, DELAY, rd);
        check(ref_model, "DELAY write 0x7B", 32'h0000_007B, rd);
        apb_wr(ref_model, coverage, DELAY, 32'h0000_0000);
        apb_rd(ref_model, coverage, DELAY, rd);
        check(ref_model, "DELAY write 0x00", 32'h0000_0000, rd);
        
        $display("[INFO] reg_access_test: Phase 3 — Reserved offset checks");
        begin
            bit [7:0] rsvd_addrs[] = '{8'h24, 8'h28, 8'h2C, 8'h30, 8'h40, 8'hFC};
            foreach (rsvd_addrs[i]) begin
                // Write a non-zero value to the reserved offset
                tb_top.u_apb_bfm.apb_write(rsvd_addrs[i], 32'hDEAD_BEEF);
                coverage.sample_register(rsvd_addrs[i], 1'b1);
                // Read it back — must be 0
                tb_top.u_apb_bfm.apb_read(rsvd_addrs[i], rd);
                coverage.sample_register(rsvd_addrs[i], 1'b0);
                check(ref_model,
                      $sformatf("RSVD[0x%02h] read", rsvd_addrs[i]),
                      32'h0000_0000, rd);
            end
        end
        
        $display("[INFO] reg_access_test: Phase 4 — Read-only / write-only checks");
        // STATUS: read the current value, attempt to write, read again — must match
        apb_rd(ref_model, coverage, STATUS, rd);
        begin
            bit [31:0] status_before = rd;
            tb_top.u_apb_bfm.apb_write(STATUS, 32'hFFFF_FFFF);
            coverage.sample_register(STATUS, 1'b1);
            apb_rd(ref_model, coverage, STATUS, rd);
            check(ref_model, "STATUS unchanged after write", status_before, rd);
        end
        // TX_DATA: reads always return 0 regardless of prior writes
        // (EN=0 currently, so writes are silently ignored anyway per R3)
        tb_top.u_apb_bfm.apb_write(TX_DATA, 32'h1234_5678);
        coverage.sample_register(TX_DATA, 1'b1);
        apb_rd(ref_model, coverage, TX_DATA, rd);
        check(ref_model, "TX_DATA read always 0", 32'h0000_0000, rd);
        
        $display("[INFO] reg_access_test: Phase 5 — Walking-1s on CTRL");
        begin
            int bit_pos;
            for (bit_pos = 0; bit_pos < 8; bit_pos++) begin
                bit [31:0] pattern = (32'h1 << bit_pos);
                apb_wr(ref_model, coverage, CTRL, pattern);
                apb_rd(ref_model, coverage, CTRL, rd);
                check(ref_model,
                      $sformatf("CTRL walking-1 bit%0d", bit_pos),
                      pattern, rd);
            end
            // Restore CTRL to 0
            apb_wr(ref_model, coverage, CTRL, 32'h0000_0000);
        end
        
        $display("[INFO] reg_access_test: Phase 6 — Walking-1s on CLK_DIV");
        begin
            int bit_pos;
            for (bit_pos = 0; bit_pos < 16; bit_pos++) begin
                bit [31:0] pattern = (32'h1 << bit_pos);
                apb_wr(ref_model, coverage, CLK_DIV, pattern);
                apb_rd(ref_model, coverage, CLK_DIV, rd);
                check(ref_model,
                      $sformatf("CLK_DIV walking-1 bit%0d", bit_pos),
                      pattern, rd);
            end
            // Restore CLK_DIV to 0
            apb_wr(ref_model, coverage, CLK_DIV, 32'h0000_0000);
        end
        
        $display("[INFO] reg_access_test: Phase 7 — Cross-register isolation");
        apb_wr(ref_model, coverage, CTRL,    32'h0000_0055);  // bits[7:0]
        apb_wr(ref_model, coverage, CLK_DIV, 32'h0000_ABCD);  // bits[15:0]
        apb_wr(ref_model, coverage, SS_CTRL, 32'h0000_0039);  // bits[7:0]
        apb_wr(ref_model, coverage, INT_EN,  32'h0000_000A);  // bits[4:0]
        apb_wr(ref_model, coverage, DELAY,   32'h0000_0042);  // bits[7:0]
        apb_rd(ref_model, coverage, CTRL, rd);
        check(ref_model, "CTRL isolation", 32'h0000_0055, rd);
        apb_rd(ref_model, coverage, CLK_DIV, rd);
        check(ref_model, "CLK_DIV isolation", 32'h0000_ABCD, rd);
        apb_rd(ref_model, coverage, SS_CTRL, rd);
        check(ref_model, "SS_CTRL isolation", 32'h0000_0039, rd);
        apb_rd(ref_model, coverage, INT_EN, rd);
        check(ref_model, "INT_EN isolation", 32'h0000_000A, rd);
        apb_rd(ref_model, coverage, DELAY, rd);
        check(ref_model, "DELAY isolation", 32'h0000_0042, rd);
        // Clean up — disable EN to reset FIFOs
        apb_wr(ref_model, coverage, CTRL,    32'h0000_0000);
        apb_wr(ref_model, coverage, CLK_DIV, 32'h0000_0000);
        apb_wr(ref_model, coverage, SS_CTRL, 32'h0000_0000);
        apb_wr(ref_model, coverage, INT_EN,  32'h0000_0000);
        apb_wr(ref_model, coverage, DELAY,   32'h0000_0000);
        
        $display("[INFO] reg_access_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask
endclass
`endif // REG_ACCESS_TEST_SV