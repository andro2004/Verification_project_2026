// =============================================================================
// spi_slave_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal SPI slave responder. Drives MISO with a configurable pattern that
// is rotated on every sampled SCLK edge. Students should extend this to
// capture the MOSI stream into a queue and expose it to their scoreboard.
//
// This BFM mirrors the SPI mode from the DUT's CTRL register via a shared
// testbench "mode" input. Students MUST keep it in lock-step with CTRL.MODE
// when writing new tests.
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave  spi,
    input  logic  [1:0] mode,        // {CPOL, CPHA}
    input  logic  [31:0] miso_data,    // pattern repeatedly returned on MISO
    input  logic  lsb_first,
    input  logic [1:0] width
    
);

    logic sclk_q;   // SCLK previous value for edge detection
    int   bit_idx;  // which bit of miso_data is currently on the line

    wire CPOL  = mode[1];
    wire CPHA  = mode[0];
    wire sample_posedge = (CPOL == CPHA);
    wire ss_act = (spi.ss_n != 4'hF);
    int bits_count;
    logic word_done = 0;
    logic rising;
    logic falling;
    logic [31:0] mosi_data;
    logic [31:0] mosi_q [$];
    initial begin
        spi.cb_slave.miso <= 1'b0;
        sclk_q  = CPOL;
    end

    always_comb begin
        if(width == 0)
            bits_count = 8;
        else if(width == 1)
            bits_count = 16;
        else if(width == 2)
            bits_count = 32;
        else 
            bits_count = 8;
    end
    // MISO shifter. For simplicity this BFM only supports CPOL=0 / CPHA=0
    // (mode 0). Students should generalise to all four modes to catch the
    // mode_coverage_test bugs.
    always @(posedge spi.pclk) begin
        if (!ss_act) begin
            bit_idx <= (lsb_first)? 0:bits_count-1;
            spi.cb_slave.miso <= (CPHA == 0) ? miso_data[(lsb_first)? 0:bits_count-1] : 1'b0;
            mosi_data <= '0;
            sclk_q <= CPOL;
            word_done <= 1'b0;
        end else begin
            // Change MISO on the falling edge of SCLK (mode 0 convention
            // from the DUT's perspective: setup on falling, sample on rising)
            if(word_done)
            begin
                mosi_q.push_back(mosi_data);
                mosi_data <= '0;
                word_done <= 1'b0;
            end
                
            rising  = (sclk_q == 0 && spi.sclk == 1);
            falling = (sclk_q == 1 && spi.sclk == 0);
            case (sample_posedge) 
                1'b0:
                begin
                    //lanching
                if (rising) begin
                    spi.cb_slave.miso <= miso_data[bit_idx];
                end
                //sampling
                if (falling) begin
                    mosi_data[bit_idx]<=spi.mosi;
                    if(lsb_first) begin
                            if(bit_idx == bits_count-1)
                            begin
                                bit_idx<=0;
                                word_done <= 1'b1;
                            end
                            else
                            begin
                                bit_idx <= bit_idx + 1;
                            end
                    end else begin
                            if(bit_idx == 0)
                            begin
                                bit_idx<= bits_count-1;
                                word_done <= 1'b1;
                            end
                            else
                            begin
                                bit_idx <= bit_idx - 1;
                            end
                    end
                end
                end

                1'b1:
                begin
                    //lanching
                if (falling) begin
                        spi.cb_slave.miso <= miso_data[bit_idx];
                end    

                //sampling
                if (rising) begin
                    mosi_data[bit_idx]<=spi.mosi;
                    if(lsb_first) begin
                            if(bit_idx == bits_count-1)
                            begin
                                bit_idx<=0;
                                word_done <= 1'b1;
                            end
                            else
                            begin
                                bit_idx <= bit_idx + 1;
                            end
                    end else begin
                            if(bit_idx == 0)
                            begin
                                bit_idx<= bits_count-1;
                                word_done <= 1'b1;
                            end
                            else
                            begin
                                bit_idx <= bit_idx - 1;
                            end
                    end
                end 
                end

            endcase
            
            sclk_q <= spi.sclk;
        end
    end

endmodule

`endif // SPI_SLAVE_BFM_SV
