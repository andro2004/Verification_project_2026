// =============================================================================
// spi_regfile_sva.sv
// -----------------------------------------------------------------------------
// SystemVerilog Assertions bound to `u_regfile` module in the SPI Master DUT.
// =============================================================================

`ifndef SPI_REGFILE_SVA_SV
`define SPI_REGFILE_SVA_SV

module spi_regfile_sva (
    input logic PCLK, PRESETn,
    input logic PSEL, PENABLE, PREADY, PSLVERR,
    // Add required internal taps like interrupt flags, FIFO pointers...
    input logic IRQ,
    input logic ctrl_en,
    input logic [4:0] INT_STAT, INT_EN
);

    // Aggregate IRQ is OR of all five sticky status bits (R18)
    a_irq_agg : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            IRQ == |INT_STAT
    ) else $error("[ASSERTION_ERROR] a_irq_agg IRQ=%b int_stat=%b",
                  IRQ, INT_STAT);

    // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    a_irq_off_when_disabled : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (!ctrl_en) |-> ##[0:1] (IRQ == 1'b0 || INT_STAT != 0)
    ) else $error("[ASSERTION_ERROR] a_irq_off_when_disabled");

    // =========================================================================
    // Skeleton Assertions - Implementation Required
    // =========================================================================
    
    // a_apb_psel_2clk: PSEL=1 for at least 2 PCLK to complete a transaction.
    // TODO: Implement assertion
    
    // a_apb_penable: PENABLE must only assert while PSEL=1.
    // TODO: Implement assertion
    
    // a_apb_stable_bus: PADDR, PWRITE, PWDATA stable from SETUP to ACCESS of the same transaction.
    // TODO: Implement assertion
    
    // a_fifo_no_push_full (Req R13): No push when full (after OVF clear) without explicit OVF assertion.
    // TODO: Implement assertion
    
    // a_apb_zero_ws (Req R22): Check that PREADY always equals 1 (zero wait states).
    // TODO: Implement assertion
    
    // a_fifo_bounds (Req R11, R12): Ensure TX and RX FIFO pointers never exceed depth of 8.
    // TODO: Implement assertion
    
    // a_w1c_race (Req R18): Verify that a W1C write plus a simultaneous hardware event keeps the bit set.
    // TODO: Implement assertion

endmodule

`endif // SPI_REGFILE_SVA_SV
