// =============================================================================
// stim_lib.sv
// -----------------------------------------------------------------------------
// Reusable randomisable transaction classes and sequence library.
// Tests `new` these, call `randomize()`, and drive the resulting fields
// through the APB master BFM via hierarchical reference to tb_top.u_apb_bfm.
//
// Two classes are provided:
//   spi_txn            — one randomisable transaction descriptor
//   spi_sequence_lib   — static helper tasks every test can call
// =============================================================================

`ifndef SPI_STIM_LIB_SV
`define SPI_STIM_LIB_SV

// ---------------------------------------------------------------------------
// Register address aliases (mirror apb_master_bfm.sv — never hard-code 'em)
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

// STATUS bit positions (from apb_regfile.sv status_word construction)
localparam int SL_STATUS_BUSY     = 0;
localparam int SL_STATUS_TX_FULL  = 1;
localparam int SL_STATUS_TX_EMPTY = 2;
localparam int SL_STATUS_RX_FULL  = 3;
localparam int SL_STATUS_RX_EMPTY = 4;
localparam int SL_STATUS_TX_OVF   = 5;
localparam int SL_STATUS_RX_OVF   = 6;

// INT_STAT / INT_EN bit positions (from apb_regfile.sv localparams)
localparam int SL_IRQ_TX_EMPTY      = 0;
localparam int SL_IRQ_RX_FULL       = 1;
localparam int SL_IRQ_TX_OVF        = 2;
localparam int SL_IRQ_RX_OVF        = 3;
localparam int SL_IRQ_TRANSFER_DONE = 4;

// Maximum cycles to poll before declaring a timeout
localparam int SL_POLL_TIMEOUT = 5000;

// =============================================================================
// spi_txn — one fully randomisable SPI transfer descriptor
// =============================================================================
class spi_txn;

    // ---- Randomisable fields ------------------------------------------------
    rand bit [1:0]  mode;        // {CPOL, CPHA} — SPI modes 0-3
    rand bit        lsb_first;   // 0 = MSB first, 1 = LSB first
    rand bit [1:0]  width;       // 00=8-bit, 01=16-bit, 10=32-bit
    rand bit [15:0] clk_div;     // SCLK = PCLK / (2*(clk_div+1))
    rand bit [7:0]  delay_cfg;   // inter-transfer idle half-cycles
    rand bit [31:0] tx_data;     // payload to push into TX FIFO
    rand bit        loopback;    // 1 = internal MOSI->RX loopback
    rand bit [3:0]  ss_en;       // which SS_n lanes to drive low

    // ---- Default constraints ------------------------------------------------

    // WIDTH must never be the illegal 2'b11 encoding (R23)
    constraint c_width_legal  { width inside {2'b00, 2'b01, 2'b10}; }

    // Keep clk_div in a simulation-friendly range by default so tests don't
    // crawl. Individual tests override this when they need corner values.
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd15]}; }

    // Keep delay small by default; delay_transfer_test overrides this.
    constraint c_delay_sane   { delay_cfg inside {[8'd0 : 8'd7]}; }

    // Ensure at least one SS lane is active for real transfers.
    // Tests that want no SS asserted override this.
    constraint c_ss_active    { ss_en != 4'b0000; }

    // tx_data upper bits unused for 8-bit/16-bit; no constraint needed —
    // the hardware masks them on push (apb_regfile.sv tx_push_data logic).

    // ---- Helper: pack CTRL register word ------------------------------------
    // CTRL layout from apb_regfile.sv:
    //   [0]    EN        — always 1 (we are enabling the controller)
    //   [1]    MSTR      — always 1 (we are the master)
    //   [3:2]  MODE      — {CPOL, CPHA}
    //   [4]    LSB_FIRST
    //   [5]    LOOPBACK
    //   [7:6]  WIDTH     — 00=8b, 01=16b, 10=32b
    function bit [31:0] pack_ctrl_word();
        return {
            24'b0,
            width,          // [7:6]
            loopback,       // [5]
            lsb_first,      // [4]
            mode,           // [3:2]
            1'b1,           // [1] MSTR
            1'b1            // [0] EN
        };
    endfunction

    // ---- Helper: pack SS_CTRL register word ---------------------------------
    // SS_CTRL layout: [7:4] = ss_val, [3:0] = ss_en
    // SS_n[i] = ~ss_en[i] | ss_val[i]   (R20)
    // To assert a lane LOW: ss_en[i]=1, ss_val[i]=0 → SS_n[i] = ~1|0 = 0
    // ss_val is always 0 here (we always want asserted lanes to be LOW).
    function bit [31:0] pack_ss_ctrl_word();
        return {24'b0, 4'b0000, ss_en};   // ss_val=0, ss_en=ss_en
    endfunction

    // ---- Helper: number of data bits in this transfer -----------------------
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

// =============================================================================
// spi_txn_clkdiv_corner — forces corner DIV values (TC-07)
// Inherits all fields from spi_txn; only overrides the clk_div constraint.
// =============================================================================
class spi_txn_clkdiv_corner extends spi_txn;

    // Override parent's sane constraint with the corner-case set
    constraint c_clk_div_sane {
        clk_div inside {
            16'd0,          // R24: PCLK/2 minimum
            16'd1,
            16'd2,
            16'd3,
            16'd255,
            16'd1024,
            16'd65535       // R25: minimum SCLK frequency
        };
    }

endclass

// =============================================================================
// spi_txn_fifo — forces occupancy-friendly payload count (TC-05)
// =============================================================================
class spi_txn_fifo extends spi_txn;

    rand int unsigned burst_len;   // how many words to push in one burst

    // Stay within FIFO depth; individual tasks control fill level
    constraint c_burst_len { burst_len inside {[1:8]}; }

    // Fast clock so FIFO stress doesn't take forever
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd3]}; }

endclass

// =============================================================================
// spi_txn_delay — forces delay corner values (TC-09)
// =============================================================================
class spi_txn_delay extends spi_txn;

    constraint c_delay_sane {
        delay_cfg inside {8'd0, 8'd1, [8'd128 : 8'd255]};
    }

    // Fast clock so the delay cycles are the bottleneck, not the transfer
    constraint c_clk_div_sane { clk_div inside {[16'd0 : 16'd3]}; }

endclass

// =============================================================================
// spi_sequence_lib — static task library
//
// Every task reaches the APB BFM via the hierarchical path
//   tb_top.u_apb_bfm.apb_write(addr, data)
//   tb_top.u_apb_bfm.apb_read (addr, data)
//
// This is the same pattern used by sanity_test.sv. The tasks are static so
// tests call them without needing an object handle:
//   spi_sequence_lib::configure_dut(txn);
// =============================================================================
class spi_sequence_lib;

    // =========================================================================
    // configure_dut
    // -------------------------------------------------------------------------
    // Writes CLK_DIV, DELAY, INT_EN (all sources enabled), and CTRL in the
    // correct order. Mirrors writes to the reference model.
    // =========================================================================
    static task configure_dut(spi_txn txn, ref spi_ref_model ref_model);
        // 1. Clock divider — must be written before EN=1 (R8 / R25)
        tb_top.u_apb_bfm.apb_write(SL_CLK_DIV, {16'b0, txn.clk_div});
        ref_model.apb_write(SL_CLK_DIV, {16'b0, txn.clk_div});

        // 2. Inter-transfer delay (R21)
        tb_top.u_apb_bfm.apb_write(SL_DELAY, {24'b0, txn.delay_cfg});
        ref_model.apb_write(SL_DELAY, {24'b0, txn.delay_cfg});

        // 3. Enable all five interrupt sources so scoreboard can observe them
        tb_top.u_apb_bfm.apb_write(SL_INT_EN, 32'h0000_001F);
        ref_model.apb_write(SL_INT_EN, 32'h0000_001F);

        // 4. CTRL last
        tb_top.u_apb_bfm.apb_write(SL_CTRL, txn.pack_ctrl_word());
        ref_model.apb_write(SL_CTRL, txn.pack_ctrl_word());
    endtask

    // Wrapper: allow callers to invoke configure_dut(txn) without passing
    // a reference to the model. This keeps existing tests working and
    // implicitly uses the tb_top.u_ref instance.
    static task configure_dut(spi_txn txn);
        configure_dut(txn, tb_top.u_ref);
    endtask

    // =========================================================================
    // target_ss
    // -------------------------------------------------------------------------
    // Asserts or de-asserts slave-select lanes.
    // =========================================================================
    static task target_ss(bit [3:0] ss_en_bits, ref spi_ref_model ref_model);
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, {24'b0, 4'b0000, ss_en_bits});
        ref_model.apb_write(SL_SS_CTRL, {24'b0, 4'b0000, ss_en_bits});
    endtask

    // Wrapper that uses the global ref model instance if caller omits it.
    static task target_ss(bit [3:0] ss_en_bits);
        target_ss(ss_en_bits, tb_top.u_ref);
    endtask

    // =========================================================================
    // push_single
    // -------------------------------------------------------------------------
    // Writes one word to TX_DATA.
    // =========================================================================
    static task push_single(spi_txn txn, ref spi_ref_model ref_model);
        tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn.tx_data);
        ref_model.apb_write(SL_TX_DATA, txn.tx_data);
    endtask

    // Wrapper to keep existing call sites working without passing ref_model
    static task push_single(spi_txn txn);
        push_single(txn, tb_top.u_ref);
    endtask

    // =========================================================================
    // push_burst
    // -------------------------------------------------------------------------
    // Pushes every transaction in txn_q[] to TX_DATA sequentially.
    // =========================================================================
    static task push_burst(spi_txn txn_q[$], ref spi_ref_model ref_model);
        foreach (txn_q[i]) begin
            tb_top.u_apb_bfm.apb_write(SL_TX_DATA, txn_q[i].tx_data);
            ref_model.apb_write(SL_TX_DATA, txn_q[i].tx_data);
        end
    endtask

    // Wrapper variant
    static task push_burst(spi_txn txn_q[$]);
        push_burst(txn_q, tb_top.u_ref);
    endtask

    // =========================================================================
    // pop_rx_burst
    // -------------------------------------------------------------------------
    // Drains the RX FIFO into rx_q[] until RX_EMPTY is asserted.
    // Polls STATUS before each read so it never reads an empty FIFO (which
    // would return 0 per R15 without setting RX_OVF).
    //
    // The caller must have waited for BUSY=0 (wait_idle) before calling,
    // otherwise not all transfers will have populated the RX FIFO yet.
    // =========================================================================
    static task pop_rx_burst(output bit [31:0] rx_q[$]);
        bit [31:0] status, rdata;
        rx_q = {};   // clear output queue

        // Read STATUS, pop while RX_EMPTY=0
        apb_read_sync(SL_STATUS, status);
        while (!status[SL_STATUS_RX_EMPTY]) begin
            apb_read_sync(SL_RX_DATA, rdata);
            rx_q.push_back(rdata);
            apb_read_sync(SL_STATUS, status);
        end
    endtask

    // =========================================================================
    // apb_read_sync
    // -------------------------------------------------------------------------
    // Reads an APB register from both hardware and the reference model.
    // This keeps the SW model state aligned with the real DUT state.
    // For RX_DATA reads, both sides pop one entry from their RX FIFO.
    // =========================================================================
    static task apb_read_sync(input bit [7:0] addr,
                              output bit [31:0] data,
                              ref spi_ref_model ref_model);
        tb_top.u_apb_bfm.apb_read(addr, data);
        ref_model.apb_read(addr);
    endtask

    // Wrapper variant using the default reference model instance.
    static task apb_read_sync(input bit [7:0] addr,
                              output bit [31:0] data);
        apb_read_sync(addr, data, tb_top.u_ref);
    endtask

    // =========================================================================
    // wait_idle
    // -------------------------------------------------------------------------
    // Polls STATUS.BUSY until it clears. Prints a timeout error if the DUT
    // is still busy after SL_POLL_TIMEOUT APB reads so a stuck FSM is caught
    // immediately rather than hanging the simulation indefinitely.
    // =========================================================================
    static task wait_idle();
        bit [31:0] status;
        int cycles = 0;

        tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
        while (status[SL_STATUS_BUSY]) begin
            if (cycles >= SL_POLL_TIMEOUT) begin
                $display("[CHECKER_ERROR] wait_idle: BUSY still asserted after %0d polls — DUT hung?",
                         SL_POLL_TIMEOUT);
                return;
            end
            tb_top.u_apb_bfm.apb_read(SL_STATUS, status);
            cycles++;
        end
    endtask

    // =========================================================================
    // read_status
    // -------------------------------------------------------------------------
    // Convenience wrapper — reads STATUS and returns the full word.
    // Tests can inspect individual bits using the SL_STATUS_* localparams.
    // =========================================================================
    static task read_status(output bit [31:0] status);
        apb_read_sync(SL_STATUS, status);
    endtask

    // =========================================================================
    // clear_interrupts
    // -------------------------------------------------------------------------
    // Reads INT_STAT and immediately writes it back as a W1C clear.
    // Returns the value that was set BEFORE the clear so callers can check
    // which sources fired.
    //
    // The W1C mechanism in the DUT (R18):
    //   next_stat = int_stat & ~PWDATA   (clear requested bits)
    //   then OR in any new hardware events the SAME cycle
    // So this task correctly captures and clears without hiding a racing event.
    // =========================================================================
    static task clear_interrupts(output bit [31:0] int_stat_before);
        tb_top.u_apb_bfm.apb_read (SL_INT_STAT, int_stat_before);
        // Write back the same value — 1s in PWDATA clear the corresponding bits
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT, int_stat_before);
        // Mirror the clear into the reference model so its W1C logic updates
        tb_top.u_ref.apb_write(SL_INT_STAT, int_stat_before);
    endtask

    // Variant that allows an explicit ref_model (keeps API consistent)
    static task clear_interrupts(output bit [31:0] int_stat_before, ref spi_ref_model ref_model);
        tb_top.u_apb_bfm.apb_read (SL_INT_STAT, int_stat_before);
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT, int_stat_before);
        ref_model.apb_write(SL_INT_STAT, int_stat_before);
    endtask

    // =========================================================================
    // inject_error
    // -------------------------------------------------------------------------
    // Writes arbitrary data to any register offset, including reserved ones
    // (0x24+). Used by error_injection_test to verify:
    //   - Reserved offsets ignore writes and return 0 (R22/R23)
    //   - TX_DATA write to a full FIFO sets TX_OVF (R13)
    //   - Reads of empty RX_DATA return 0 without setting RX_OVF (R15)
    //
    // Returns the readback so the caller can compare against the expected
    // value (0 for reserved offsets, last-written for normal registers).
    // =========================================================================
    static task inject_error(input  bit [7:0]  addr,
                             input  bit [31:0] data,
                             output bit [31:0] readback);
        tb_top.u_apb_bfm.apb_write(addr, data);
        tb_top.u_apb_bfm.apb_read (addr, readback);
    endtask

    // =========================================================================
    // do_transfer
    // -------------------------------------------------------------------------
    // High-level "do one complete transfer" helper used by sanity_test and
    // mode_coverage_test. Sequence:
    //   1. configure_dut with the transaction
    //   2. Set BFM slave mode to match (caller must set tb_top.bfm_mode first)
    //   3. push_single → assert SS → wait_idle → deassert SS
    //   4. Return RX word
    //
    // The caller is responsible for setting tb_top.bfm_mode and
    // tb_top.bfm_pattern before calling so the slave BFM responds correctly.
    // =========================================================================
    static task do_transfer(spi_txn txn, output bit [31:0] rx_word);
        configure_dut(txn);
        push_single(txn);
        target_ss(txn.ss_en);
        wait_idle();
        target_ss(4'b0000);           // deassert all SS_n lanes
        tb_top.u_apb_bfm.apb_read(SL_RX_DATA, rx_word);
    endtask

    // =========================================================================
    // do_burst_transfer
    // -------------------------------------------------------------------------
    // High-level helper for multi-word bursts (fifo_stress_test,
    // delay_transfer_test). Sequence:
    //   1. configure_dut with the first transaction (all share same config)
    //   2. push_burst entire queue
    //   3. Assert SS and wait for all transfers to complete (BUSY clears)
    //   4. Drain RX FIFO into rx_q
    // =========================================================================
    static task do_burst_transfer(spi_txn txn_q[$], output bit [31:0] rx_q[$]);
        if (txn_q.size() == 0) return;

        // All words in a burst share the same config — use the first entry
        configure_dut(txn_q[0]);
        push_burst(txn_q);
        target_ss(txn_q[0].ss_en);
        wait_idle();
        target_ss(4'b0000);
        pop_rx_burst(rx_q);
    endtask

    // =========================================================================
    // reset_dut
    // -------------------------------------------------------------------------
    // Disable the controller (EN=0) to flush FIFOs and hold SCLK idle.
    // Useful between sub-tests inside a single test to start from a clean state
    // without re-applying PRESETn (which would require tb_top involvement).
    // =========================================================================
    static task reset_dut();
        // Writing CTRL=0 clears EN. The RTL resets FIFO pointers when EN=0.
        tb_top.u_apb_bfm.apb_write(SL_CTRL,    32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(SL_SS_CTRL, 32'h0000_0000);  // deassert all SS
        tb_top.u_apb_bfm.apb_write(SL_INT_EN,  32'h0000_0000);  // mask all IRQs
        tb_top.u_apb_bfm.apb_write(SL_INT_STAT,32'h0000_001F);  // W1C clear all
        // Mirror reset actions into the reference model so it stays in sync
        tb_top.u_ref.apb_write(SL_CTRL,    32'h0000_0000);
        tb_top.u_ref.apb_write(SL_SS_CTRL, 32'h0000_0000);
        tb_top.u_ref.apb_write(SL_INT_EN,  32'h0000_0000);
        tb_top.u_ref.apb_write(SL_INT_STAT,32'h0000_001F);
    endtask

endclass

`endif // SPI_STIM_LIB_SV
