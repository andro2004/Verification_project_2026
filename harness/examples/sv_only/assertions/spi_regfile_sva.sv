// =============================================================================
// spi_regfile_sva.sv
// -----------------------------------------------------------------------------
// SystemVerilog Assertions bound to `u_regfile` module in the SPI Master DUT.
// =============================================================================

`ifndef SPI_REGFILE_SVA_SV
`define SPI_REGFILE_SVA_SV

module spi_regfile_sva (
    input logic PCLK, 
    input logic PRESETn,
    input logic PSEL, 
    input logic PENABLE, 
    input logic PREADY, 
    input logic PSLVERR,
    input logic IRQ,
    input logic ctrl_en,
    input logic [4:0] INT_STAT, 
    input logic [4:0] INT_EN,

    input logic FULL,      
    input logic OVF,       
    input logic push,      
    input logic [3:0] tx_ptr,    
    input logic [3:0] rx_ptr,
    input logic [7:0] PADDR,
    input logic PWRITE,
    input logic [31:0] PWDATA,
    input logic [4:0] hw_event  //harware events mapping to the 5 interrupts
);


                                                                                                                                       
    // Aggregate IRQ is OR of all five sticky status bits (R18)
    a_irq_agg : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            IRQ == |(INT_STAT & INT_EN)
    ) else $error("ERROR: a_irq_agg IRQ=%b, calculated=%b (INT_STAT=%b, INT_EN=%b)",
                  IRQ, |(INT_STAT & INT_EN), INT_STAT, INT_EN);

    // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    a_irq_off_when_disabled : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (!ctrl_en) |-> ##[0:1] (IRQ == 1'b0)
    ) else $error("ERROR: a_irq_off_when_disabled: IRQ active when CTRL.EN is disabled");

    // =========================================================================
    // Skeleton Assertions - Implementation Required
    // =========================================================================
    
    // a_apb_psel_2clk: PSEL=1 for at least 2 PCLK to complete a transaction.
    property apb_psel_two_cycles;
        @(posedge PCLK)
        $rose(PSEL) |-> PSEL ##1 PSEL;
    endproperty
    a_apb_psel_2clk: assert property(apb_psel_two_cycles)
        else $error("ERROR: PSEL dropped too early!");
    
    // a_apb_penable: PENABLE must only assert while PSEL=1.
    property apb_penable_requires_psel;
        @(posedge PCLK)
        PENABLE |-> PSEL;
    endproperty
    a_apb_penable: assert property(apb_penable_requires_psel)
        else $error("ERROR: PENABLE high while PSEL is low!");

    // a_apb_stable_bus: PADDR, PWRITE, PWDATA stable from SETUP to ACCESS of the same transaction.
    property apb_signals_stable;
        @(posedge PCLK)
        (PSEL && !PENABLE)      // setup phase (PSEL==1, PENABLE==1)
        |=> $stable(PADDR) && $stable(PWRITE) && $stable(PWDATA);   // next clk cycle must be in active phase
    endproperty
    a_apb_stable_bus: assert property(apb_signals_stable)
        else $error("ERROR: APB control/data bus signals unstable during transfer phase!");

    // a_fifo_no_push_full (Req R13): No push when full (after OVF clear) without explicit OVF assertion.
    property fifo_no_push_when_full;
        @(posedge PCLK)
        (FULL && !OVF) |-> !push;
    endproperty
    a_fifo_no_push_full: assert property(fifo_no_push_when_full)
        else $error("ERROR: Prohibited push detected while FIFO is full!");
    
    // a_apb_zero_ws (Req R22): Check that PREADY always equals 1 (zero wait states).
    a_apb_zero_ws : assert property (@(posedge PCLK) PSEL |-> PREADY)
        else $error("ERROR: Zero-wait state violation: PREADY is low during access");

    // a_fifo_bounds (Req R11, R12): Ensure TX and RX FIFO pointers never exceed depth of 8.
    a_fifo_bounds : assert property (@(posedge PCLK) (tx_ptr <= 4'd8) && (rx_ptr <= 4'd8))
        else $error("ERROR: FIFO pointer overflow! TX=%d, RX=%d", tx_ptr, rx_ptr);

    // a_w1c_race (Req R18): Verify that a W1C write plus a simultaneous hardware event keeps the bit set.
    property p_w1c_race;
        @(posedge PCLK) disable iff (!PRESETn)
        // Checking W1C race for all status bits simultaneously 
        (PSEL && PENABLE && PWRITE && (PADDR == 8'h1C)) |=> 
        ((INT_STAT & $past(hw_event)) == $past(hw_event));
    endproperty
    a_w1c_race: assert property(p_w1c_race)
        else $error("ERROR: W1C race lost: incoming hardware event was cleared by active write!");
endmodule

`endif // SPI_REGFILE_SVA_SV
