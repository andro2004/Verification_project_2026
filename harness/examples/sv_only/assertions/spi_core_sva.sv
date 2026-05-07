// =============================================================================
// spi_core_sva.sv
// -----------------------------------------------------------------------------
// SystemVerilog Assertions bound to `u_core` module in the SPI Master DUT.
// =============================================================================

`ifndef SPI_CORE_SVA_SV
`define SPI_CORE_SVA_SV

module spi_core_sva (
    input logic clk, rst_n,
    input logic sclk, mosi, cpol, cpha,
    // Add required internal taps...
    input logic [3:0] ss_n
);

    // =========================================================================
    // Skeleton Assertions - Implementation Required
    // =========================================================================
    
    // a_sclk_idle (Req R4): SCLK idle level matches CPOL whenever not transferring (BUSY=0).
    // TODO: Implement assertion
    
    // a_mosi_stable (Req R5): MOSI stable for at least 1 PCLK around each sample edge (WIRE-STABILITY).
    // TODO: Implement assertion
    
    // a_ss_stable (Req R20): SS_n held asserted for the entire WIDTH-bit transfer.
    // TODO: Implement assertion
    
    // a_xfer_length (Req R7): Verify that a transfer takes exactly WIDTH SCLK cycles.
    // TODO: Implement assertion

endmodule

`endif // SPI_CORE_SVA_SV
