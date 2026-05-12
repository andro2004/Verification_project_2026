// =============================================================================
// ref_model.sv
// -----------------------------------------------------------------------------
// A plain-SV reference model + scoreboard. Models the full spec of the SPI
// Master Controller (R1–R25) by providing APB register access methods, SPI
// transfer prediction, interrupt prediction, SCLK timing, and delay prediction.
// =============================================================================

`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // Running error count. tb_top reads this to emit the final
    // [TEST_PASSED]/[TEST_FAILED] line.
    int error_count = 0;

    // Registers
    bit [31:0] ctrl;
    bit [31:0] clk_div;
    bit [31:0] ss_ctrl;
    bit [31:0] int_en;
    bit [31:0] int_stat;
    bit [31:0] delay_reg;

    // FIFOs
    bit [31:0] tx_fifo[$];
    bit [31:0] rx_fifo[$];

    // Status bits tracked explicitly
    bit busy;
    bit rx_ovf;
    bit tx_ovf;

    // Predictor state for SPI pipeline
    bit [31:0] pred_rx_fifo[$];
    bit [31:0] pred_tx_fifo[$];

    function new();
        reset();
    endfunction

    // R2: All registers return their specified reset values after PRESETn.
    function void reset();
        error_count  = 0;
        ctrl         = 32'h0000_0000;
        clk_div      = 32'h0000_0000;
        ss_ctrl      = 32'h0000_0000;
        int_en       = 32'h0000_0000;
        int_stat     = 32'h0000_0000;
        delay_reg    = 32'h0000_0000;

        tx_fifo.delete();
        rx_fifo.delete();

        busy   = 0;
        rx_ovf = 0;
        tx_ovf = 0;

        pred_rx_fifo.delete();
        pred_tx_fifo.delete();
    endfunction

    // =========================================================================
    // Helpers — STATUS, IRQ, SCLK, SPI Mode, SS_n, DELAY, transfer width
    // =========================================================================

    // Compute dynamic STATUS register (R1, R9–R12)
    function bit [31:0] get_status();
        bit [31:0] st = 32'h0;
        st[6] = rx_ovf;                    // RX_OVF  (sticky)
        st[5] = tx_ovf;                    // TX_OVF  (sticky)
        st[4] = (rx_fifo.size() == 0);     // RX_EMPTY
        st[3] = (rx_fifo.size() == 8);     // RX_FULL
        st[2] = (tx_fifo.size() == 0);     // TX_EMPTY
        st[1] = (tx_fifo.size() == 8);     // TX_FULL
        st[0] = busy;                      // BUSY
        return st;
    endfunction

    // R16: IRQ = |(INT_STAT & INT_EN)
    function bit predict_irq();
        return |(int_stat[4:0] & int_en[4:0]);
    endfunction

    // R8/R24: SCLK half-period in PCLK cycles = (DIV+1)
    function int predict_sclk_half_period();
        return int'(clk_div[15:0]) + 1;
    endfunction

    // R8/R24: Full SCLK period in PCLK cycles = 2*(DIV+1)
    function int predict_sclk_period();
        return 2 * (int'(clk_div[15:0]) + 1);
    endfunction

    // R4: CPOL (Clock Polarity) - Idle state of SCLK
    function bit predict_cpol();
        return ctrl[3];
    endfunction

    // R5: CPHA (Clock Phase) - Sampling edge definition
    function bit predict_cpha();
        return ctrl[2];
    endfunction

    // LSB First vs MSB First configuration
    function bit predict_lsb_first();
        return ctrl[4];
    endfunction

    // R3/R4: SCLK idle state prediction (stays at CPOL when EN=0 or between transfers)
    function bit predict_sclk_idle();
        return ctrl[3]; 
    endfunction

    // R6/R7: Number of SCLK cycles per transfer
    function int get_transfer_bits();
        case (ctrl[7:6])
            2'b00:   return 8;
            2'b01:   return 16;
            default: return 32;
        endcase
    endfunction

    // R21: Expected inter-transfer delay in SCLK half-cycles
    function int predict_delay_half_cycles();
        return int'(delay_reg[7:0]);
    endfunction

    // R21: Expected inter-transfer delay in PCLK cycles
    function int predict_delay_pclk_cycles();
        return predict_delay_half_cycles() * predict_sclk_half_period();
    endfunction

    // R20: SS_n[i] = ~ss_en[i] | ss_val[i]
    function bit [3:0] predict_ss_n();
        bit [3:0] ss_en  = ss_ctrl[3:0];
        bit [3:0] ss_val = ss_ctrl[7:4];
        return ~ss_en | ss_val;
    endfunction

    // =========================================================================
    // BUSY management (R7: BUSY deasserts after last sample edge)
    // =========================================================================

    // Call when a transfer begins (TX popped, shifting starts)
    function void mark_transfer_start();
        busy = 1;
    endfunction

    // Call when a transfer finishes. Updates rx_fifo, int_stat, and busy.
    // This is the unified "transfer done" entry point that keeps the
    // register-model path (rx_fifo, int_stat) in sync with the DUT.
    function void mark_transfer_done(bit [31:0] rx_miso_val);
        spi_transfer_complete(rx_miso_val);
        // If TX FIFO is empty, the controller goes idle
        if (tx_fifo.size() == 0)
            busy = 0;
    endfunction

    // =========================================================================
    // APB Write modeling (R1, R3, R9, R13, R17, R22, R23)
    // =========================================================================
    function void apb_write(bit [31:0] addr, bit [31:0] data);
        case (addr)
            32'h00: begin // CTRL
                ctrl = data & 32'h0000_00FF; // Bits 31:8 are RSVD
                // R3: EN=0 resets shifter and FIFOs (not APB registers)
                if (ctrl[0] == 1'b0) begin
                    tx_fifo.delete();
                    rx_fifo.delete();
                    pred_tx_fifo.delete();
                    pred_rx_fifo.delete();
                    tx_ovf = 0;
                    rx_ovf = 0;
                    busy = 0;
                end
            end
            32'h08: begin // TX_DATA
                if (ctrl[0] == 1'b0) begin
                    // R3: Write ignored silently if EN=0
                end else if (tx_fifo.size() < 8) begin
                    // R9: Extract data based on width
                    bit [1:0] width_cfg = ctrl[7:6];
                    bit [31:0] masked_data = 0;
                    if (width_cfg == 2'b00) masked_data = data & 32'h0000_00FF;
                    else if (width_cfg == 2'b01) masked_data = data & 32'h0000_FFFF;
                    else masked_data = data; // 2'b10 and 2'b11: full 32 bits
                    tx_fifo.push_back(masked_data);
                end else begin
                    // R13: TX write while TX_FULL=1 → discard + TX_OVF
                    tx_ovf = 1;
                    int_stat[2] = 1; // INT_STAT[TX_OVF]
                end
            end
            32'h10: clk_div   = data & 32'h0000_FFFF; // R8:  Bits 31:16 RSVD
            32'h14: ss_ctrl   = data & 32'h0000_00FF; // R20: Bits 31:8  RSVD
            32'h18: int_en    = data & 32'h0000_001F; // R16: Bits 31:5  RSVD
            32'h1C: begin // INT_STAT (W1C) — R17
                int_stat = int_stat & ~data;
                if (data[3]) rx_ovf = 0; // R14: sticky, cleared via W1C
                if (data[2]) tx_ovf = 0; // R13: sticky, cleared via W1C
            end
            32'h20: delay_reg = data & 32'h0000_00FF; // R21: Bits 31:8  RSVD
            default: ; // R22/R23: Reserved offsets ignored
        endcase
    endfunction

    // =========================================================================
    // APB Read modeling (R1, R15, R22, R23)
    // =========================================================================
    function bit [31:0] apb_read(bit [31:0] addr);
        bit [31:0] ret = 32'h0;
        case (addr)
            32'h00: ret = ctrl;
            32'h04: ret = get_status();
            32'h08: ret = 32'h0; // TX_DATA reads return 0
            32'h0C: begin // RX_DATA
                // R15: RX read when empty → 0, does NOT set RX_OVF
                if (rx_fifo.size() > 0)
                    ret = rx_fifo.pop_front();
                else
                    ret = 32'h0;
            end
            32'h10: ret = clk_div;
            32'h14: ret = ss_ctrl;
            32'h18: ret = int_en;
            32'h1C: ret = int_stat;
            32'h20: ret = delay_reg;
            default: ret = 32'h0; // R22/R23: Reserved offsets read 0
        endcase
        return ret;
    endfunction

    // =========================================================================
    // SPI transfer complete — register-model update (R9–R14, R16)
    // Called internally by mark_transfer_done(). Also available directly
    // for tests that manage busy state themselves.
    // =========================================================================
    function void spi_transfer_complete(bit [31:0] rx_miso_val);
        bit [31:0] tx_val;
        bit [31:0] rx_val;
        if (tx_fifo.size() > 0) begin
            tx_val = tx_fifo.pop_front();
            if (tx_fifo.size() == 0) begin
                int_stat[0] = 1; // TX_EMPTY event
            end

            // R19: Loopback routes MOSI→RX internally, MISO ignored
            if (ctrl[5] == 1'b1)
                rx_val = tx_val;
            else
                rx_val = rx_miso_val;

            // Mask rx_val according to WIDTH (R6)
            if (ctrl[7:6] == 2'b00) rx_val = rx_val & 32'h0000_00FF;
            else if (ctrl[7:6] == 2'b01) rx_val = rx_val & 32'h0000_FFFF;

            // R10/R12: Push to RX FIFO
            if (rx_fifo.size() < 8) begin
                rx_fifo.push_back(rx_val);
                if (rx_fifo.size() == 8)
                    int_stat[1] = 1; // RX_FULL event
            end else begin
                // R14: RX push while RX_FULL → discard + RX_OVF
                rx_ovf = 1;
                int_stat[3] = 1; // RX_OVF event
            end
            int_stat[4] = 1; // TRANSFER_DONE event
        end
    endfunction

    // =========================================================================
    // Prediction — SPI pipeline (R4–R7, R19)
    //
    // NOTE on lsb_first: This predictor assumes the slave BFM is configured
    // to match the DUT's bit ordering. When both agree on LSB/MSB-first, the
    // predicted RX value equals the MISO pattern regardless of ordering.
    // If a buggy DUT handles LSB-first incorrectly, the RX data will differ
    // from the pattern and check_rx() will catch it.
    // =========================================================================
    task predict_transfer(input bit [31:0] tx_data,
                          input bit [31:0] miso_pattern,
                          input bit        loopback,
                          input bit [1:0]  width,
                          input bit        lsb_first);
        bit [31:0] exp_tx;
        bit [31:0] exp_rx;

        // Mask tx_data based on width
        if (width == 2'b00) exp_tx = tx_data & 32'h0000_00FF;
        else if (width == 2'b01) exp_tx = tx_data & 32'h0000_FFFF;
        else exp_tx = tx_data;

        pred_tx_fifo.push_back(exp_tx);

        if (loopback) begin
            exp_rx = exp_tx;
        end else begin
            // Mask the full 32-bit miso_pattern up to the correct width
            if (width == 2'b00) begin
                exp_rx = miso_pattern & 32'h0000_00FF;
            end else if (width == 2'b01) begin
                exp_rx = miso_pattern & 32'h0000_FFFF;
            end else begin
                exp_rx = miso_pattern;
            end
        end

        pred_rx_fifo.push_back(exp_rx);
    endtask

    // Backward compatibility wrapper for 8-bit MSB-first transfers
    task predict_single_byte(input bit [7:0] tx_byte,
                             input bit [7:0] miso_pattern,
                             input bit       loopback);
        predict_transfer({24'h0, tx_byte}, {24'h0, miso_pattern}, loopback, 2'b00, 1'b0);
    endtask

    // =========================================================================
    // Scoreboard checks
    // =========================================================================

    // Check TX (MOSI) data against prediction (from SPI Monitor)
    task check_tx(input bit [31:0] observed);
        if (pred_tx_fifo.size() == 0) begin
            $display("[SCOREBOARD_ERROR] TX check: no prediction for observed=0x%08h", observed);
            error_count++;
            return;
        end
        begin
            bit [31:0] expected = pred_tx_fifo.pop_front();
            if (observed !== expected) begin
                $display("[SCOREBOARD_ERROR] TX (MOSI) mismatch: predicted=0x%08h observed=0x%08h",
                         expected, observed);
                error_count++;
            end
        end
    endtask


    // Check RX (MISO) data against prediction (from APB read)
    task check_rx(input bit [31:0] observed);
        if (pred_rx_fifo.size() == 0) begin
            $display("[SCOREBOARD_ERROR] RX check: no prediction for observed=0x%08h", observed);
            error_count++;
            return;
        end
        begin
            bit [31:0] expected = pred_rx_fifo.pop_front();
            if (observed !== expected) begin
                $display("[SCOREBOARD_ERROR] RX mismatch: predicted=0x%08h observed=0x%08h",
                         expected, observed);
                error_count++;
            end
        end
    endtask

    // Generic register check
    task check_reg(input string name,
                   input bit [31:0] expected,
                   input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            error_count++;
        end
    endtask

    // Check STATUS register against predicted state
    task check_status(input bit [31:0] observed);
        check_reg("STATUS", get_status(), observed);
    endtask

    // Check INT_STAT register against predicted state (R16/R17)
    task check_int_stat(input bit [31:0] observed);
        check_reg("INT_STAT", int_stat, observed);
    endtask

    // Check IRQ output against predicted value (R16)
    task check_irq(input bit observed);
        bit expected = predict_irq();
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] IRQ mismatch: expected=%0b observed=%0b (INT_STAT=0x%05b INT_EN=0x%05b)",
                     expected, observed, int_stat[4:0], int_en[4:0]);
            error_count++;
        end
    endtask

    // R8/R24/R25: Check measured SCLK period against formula
    // measured_pclk_cycles = number of PCLK cycles per full SCLK period
    task check_sclk_period(input int measured_pclk_cycles);
        int expected = predict_sclk_period();
        if (measured_pclk_cycles !== expected) begin
            $display("[SCOREBOARD_ERROR] SCLK period mismatch: expected=%0d PCLK cycles, measured=%0d (DIV=%0d)",
                     expected, measured_pclk_cycles, clk_div[15:0]);
            error_count++;
        end
    endtask

    // R3/R4: Check measured SCLK idle state
    task check_sclk_idle(input bit observed_sclk);
        bit expected = predict_sclk_idle();
        if (observed_sclk !== expected) begin
            $display("[SCOREBOARD_ERROR] SCLK idle mismatch: expected=%0b (CPOL=%0b) observed=%0b",
                     expected, ctrl[3], observed_sclk);
            error_count++;
        end
    endtask

    // R21: Check measured inter-transfer idle gap
    // measured_half_cycles = number of SCLK half-cycles of idle between transfers
    task check_delay(input int measured_half_cycles);
        int expected = predict_delay_half_cycles();
        if (measured_half_cycles !== expected) begin
            $display("[SCOREBOARD_ERROR] Delay mismatch: expected=%0d half-cycles, measured=%0d (DELAY_REG=%0d)",
                     expected, measured_half_cycles, delay_reg[7:0]);
            error_count++;
        end
    endtask

    // R20: Check SS_n output against predicted combinational value
    task check_ss_n(input bit [3:0] observed);
        bit [3:0] expected = predict_ss_n();
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] SS_n mismatch: expected=0x%01h observed=0x%01h (SS_CTRL=0x%02h)",
                     expected, observed, ss_ctrl[7:0]);
            error_count++;
        end
    endtask

    // R6/R7: Check that a transfer took exactly the right number of SCLK cycles
    task check_transfer_length(input int measured_sclk_cycles);
        int expected = get_transfer_bits();
        if (measured_sclk_cycles !== expected) begin
            $display("[SCOREBOARD_ERROR] Transfer length mismatch: expected=%0d SCLK cycles, measured=%0d (WIDTH=%0b)",
                     expected, measured_sclk_cycles, ctrl[7:6]);
            error_count++;
        end
    endtask

endclass

`endif // SPI_REF_MODEL_SV
