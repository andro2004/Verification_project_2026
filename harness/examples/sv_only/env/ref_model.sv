// =============================================================================
// ref_model.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// A plain-SV reference model + scoreboard. It does not use UVM - it is a
// simple class that students instantiate from tb_top (`spi_ref_model u_ref =
// new();`) and update from their test programs.
//
// Models the full spec of the SPI Master Controller (except R3) by providing
// APB register access methods and SPI transfer prediction.
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

    // R2: All registers return their specified reset values after PRESETn asserts.
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

    // Helper to compute dynamic STATUS
    function bit [31:0] get_status();
        bit [31:0] st = 32'h0;
        st[6] = rx_ovf;
        st[5] = tx_ovf;
        st[4] = (rx_fifo.size() == 0);
        st[3] = (rx_fifo.size() == 8);
        st[2] = (tx_fifo.size() == 0);
        st[1] = (tx_fifo.size() == 8);
        st[0] = busy;
        return st;
    endfunction

    // APB Write modeling
    function void apb_write(bit [31:0] addr, bit [31:0] data);
        case (addr)
            32'h00: begin // CTRL
                // Except R3: Do NOT hold shifter and FIFOs in reset if EN=0
                ctrl = data & 32'h0000_00FF; // Bits 31:8 are RSVD
                if (ctrl[0] == 1'b0) begin
                    // Only reset shifter and FIFOs as per R3 (Not the APB registers)
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
                    // Write ignored silently if EN=0
                    /*
                        mstr is used for enabling the fsm,
                        but if master is deasserted it still allows writing to the tx_fifo
                    */
                end else if (tx_fifo.size() < 8) begin
                    // Extract data based on width
                    bit [1:0] width_cfg = ctrl[7:6];
                    bit [31:0] masked_data = 0;
                    if (width_cfg == 2'b00) masked_data = data & 32'h0000_00FF; //8-bit byte
                    else if (width_cfg == 2'b01) masked_data = data & 32'h0000_FFFF; //16-bit half words
                    else masked_data = data; //32-bit words
                    /*
                        if width cfg ==11    
                        what should i do????(implementation dependend (periority of check))
                        case 1
                            masked_data = 0      
                        case 2 
                            masked_data = data
                            we check the hardware implemintation code and find that it was case 2
                            in apb_regfile.sv in line 198
                            if (apb_write && PADDR == OFF_TX_DATA && ctrl_en) begin
                                tx_push_valid = 1'b1;
                                case (ctrl_width)
                                    2'b00: tx_push_data = {24'b0, PWDATA[7:0]};
                                    2'b01: tx_push_data = {16'b0, PWDATA[15:0]};
                                    default: tx_push_data = PWDATA; ????????????????????????
                    */
                    tx_fifo.push_back(masked_data);
                end else begin // TX_FULL=1
                    tx_ovf = 1;
                    int_stat[2] = 1; // INT_STAT[TX_OVF]
                end
            end
            32'h10: clk_div = data & 32'h0000_FFFF; // Bits 31:16 are RSVD
            32'h14: ss_ctrl = data & 32'h0000_00FF; // Bits 31:8 are RSVD
            32'h18: int_en  = data & 32'h0000_001F; // Bits 31:5 are RSVD
            32'h1C: begin // INT_STAT (W1C)
                int_stat = int_stat & ~data;
                if (data[3]) rx_ovf = 0;    // (sticky, cleared via INT_STAT)  from specs
                if (data[2]) tx_ovf = 0;    // (sticky, cleared via INT_STAT)
            end
            32'h20: delay_reg = data & 32'h0000_00FF; // Bits 31:8 are RSVD
            default: ; // Reserved offsets are ignored
        endcase
    endfunction

    // APB Read modeling
    function bit [31:0] apb_read(bit [31:0] addr);
        bit [31:0] ret = 32'h0;
        case (addr)
            32'h00: ret = ctrl;
            32'h04: ret = get_status();
            32'h08: ret = 32'h0; // TX_DATA reads return 0
            32'h0C: begin // RX_DATA
                if (rx_fifo.size() > 0) begin
                    ret = rx_fifo.pop_front();
                end else begin
                    ret = 32'h0;
                end
            end
            32'h10: ret = clk_div;
            32'h14: ret = ss_ctrl;
            32'h18: ret = int_en;
            32'h1C: ret = int_stat;
            32'h20: ret = delay_reg;
            default: ret = 32'h0; // Reserved offsets read 0
        endcase
        return ret;
    endfunction

    // Model SPI transfer
    // Call this to model the DUT completing a transfer.
    function void spi_transfer_complete(bit [31:0] rx_miso_val);
        bit [31:0] tx_val;
        bit [31:0] rx_val;
        if (tx_fifo.size() > 0) begin
            tx_val = tx_fifo.pop_front();
            if (tx_fifo.size() == 0) begin
                int_stat[0] = 1; // TX_EMPTY event
            end
            
            if (ctrl[5] == 1'b1) begin // LOOPBACK
                rx_val = tx_val;
            end else begin
                rx_val = rx_miso_val;
            end
            
            // Mask rx_val according to WIDTH
            if (ctrl[7:6] == 2'b00) rx_val = rx_val & 32'h0000_00FF;
            else if (ctrl[7:6] == 2'b01) rx_val = rx_val & 32'h0000_FFFF;
            
            // Push to RX FIFO when transfer completes
            if (rx_fifo.size() < 8) begin
                rx_fifo.push_back(rx_val);
                if (rx_fifo.size() == 8) begin
                    int_stat[1] = 1; // RX_FULL event
                end
            end else begin
                rx_ovf = 1;
                int_stat[3] = 1; // RX_OVF event
            end
            int_stat[4] = 1; // TRANSFER_DONE event
        end
    endfunction

    // Model the full SPI pipeline prediction for any width
    task predict_transfer(input bit [31:0] tx_data,
                          input bit [31:0] miso_pattern,
                          input bit       loopback,
                          input bit [1:0] width,
                          input bit       lsb_first);
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
            // Replicate the 8-bit BFM miso_pattern up to the correct width
            if (width == 2'b00) begin
                exp_rx = miso_pattern & 32'h0000_00FF;
            end else if (width == 2'b01) begin
                exp_rx = {miso_pattern[7:0], miso_pattern[7:0]} & 32'h0000_FFFF;
            end else begin
                exp_rx = {miso_pattern[7:0], miso_pattern[7:0], miso_pattern[7:0], miso_pattern[7:0]};
            end
        end
        
        pred_rx_fifo.push_back(exp_rx);
    endtask

    // Backward compatibility for basic scaffold tests
    task predict_single_byte(input bit [7:0] tx_byte,
                             input bit [7:0] miso_pattern,
                             input bit       loopback);
        predict_transfer({24'h0, tx_byte}, {24'h0, miso_pattern}, loopback, 2'b00, 1'b0);
    endtask

    task check_rx(input bit [31:0] observed);
        if (pred_rx_fifo.size() == 0) begin
            $display("[SCOREBOARD_ERROR] RX check failed: No expected data predicted for observed=0x%08h", observed);
            error_count++;
            return;
        end
        
        begin
            bit [31:0] expected = pred_rx_fifo.pop_front();
            if (observed !== expected) begin
                $display("[SCOREBOARD_ERROR] RX data mismatch: predicted=0x%08h observed=0x%08h",
                         expected, observed);
                error_count++;
            end
        end
    endtask

    task check_reg(input string name,
                   input bit [31:0] expected,
                   input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            error_count++;
        end
    endtask

endclass

`endif // SPI_REF_MODEL_SV
