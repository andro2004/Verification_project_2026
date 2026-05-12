// =============================================================================
// spi_core_sva.sv
// -----------------------------------------------------------------------------
// SystemVerilog Assertions bound to u_core module in the SPI Master DUT.
// =============================================================================

`ifndef SPI_CORE_SVA_SV
`define SPI_CORE_SVA_SV

module spi_core_sva (
    input logic clk, rst_n,
    input logic sclk, mosi, cpol, cpha,
    input logic [3:0] ss_n,
    // Internal taps from the DUT clock generator
    input logic [16:0] sclk_cnt,
    input logic        sclk_phase,
    input logic [15:0] cfg_clk_div,
    
    input wire BUSY, 
    input logic [5:0] width // width in bits (8, 16, 32)
);

    // Re-derive the lead/trail indicators from internal registers (same logic as RTL)
    wire leading_strobe  = (sclk_cnt == cfg_clk_div) && (sclk_phase == 1'b0);       // sclk_phase refers to leading or trailing edge, and when clk_div cycles, passes, sckl toggles
    wire trailing_strobe = (sclk_cnt == cfg_clk_div) && (sclk_phase == 1'b1);

    // Define the sampling edge based on CPHA (Req R5/R6)
    // CPHA=0: Sample on Leading Edge
    // CPHA=1: Sample on Trailing Edge
    wire sample_edge = (cpha == 1'b0) ? leading_strobe : trailing_strobe;

    logic [5:0] pulse_cnt;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || !BUSY) 
            pulse_cnt <= 6'd0;
        else if (sample_edge)
            pulse_cnt <= pulse_cnt + 6'd1;
    end
    
    // =========================================================================
    // Skeleton Assertions - Implementation Required
    // =========================================================================
    
    // a_sclk_idle (Req R4): SCLK idle level matches CPOL whenever not transferring (BUSY=0).
    property spi_idle_clock;
        @(posedge clk)
        !BUSY |-> (sclk == cpol);
    endproperty
    a_sclk_idle: assert property(spi_idle_clock)
        else $error("SCLK idle level mismatch! SCLK=%b, CPOL=%b", sclk, cpol);
    
    // a_mosi_stable (Req R5): MOSI stable for at least 1 PCLK around each sample edge (WIRE-STABILITY).
    property spi_mosi_stable;
        @(posedge clk)
        sample_edge |-> $stable(mosi);
    endproperty
    a_mosi_stable: assert property(spi_mosi_stable)
        else $error("MOSI unstable on sample edge!");

    // a_ss_stable (Req R20): SS_n held asserted for the entire WIDTH-bit transfer.
    // Each individual SS bit must remain stable if asserted.
    property spi_ss_held_low;
        @(posedge clk)
        BUSY |-> $stable(ss_n);
    endproperty
    a_ss_stable: assert property(spi_ss_held_low)
        else $error("SS_n glitch/deassert detected during active transfer! SS_n=%b", ss_n);
    
    // a_xfer_length (Req R7): Verify that a transfer takes exactly WIDTH SCLK cycles.
    property a_xfer_length_dynamic;
        @(posedge clk)
        $fell(BUSY) |-> (pulse_cnt == width);
    endproperty
    a_xfer_length: assert property(a_xfer_length_dynamic) 
        else $error("Transfer length mismatch! Expected %d, got %d", width, pulse_cnt);

endmodule

`endif // SPI_CORE_SVA_SV
