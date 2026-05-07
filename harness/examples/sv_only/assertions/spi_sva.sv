// =============================================================================
// spi_sva.sv
// -----------------------------------------------------------------------------
// SVA top-level wrapper module. `tb_top` binds it into the design.
// We instantiate both the regfile assertions and core assertions here.
//
// NOTE: These ports are NOT final! You will need to add more ports to this
// wrapper and tap into additional internal signals from tb_top.sv's bind 
// statement to satisfy all required assertions.
// =============================================================================

`ifndef SPI_SVA_SV
`define SPI_SVA_SV
`timescale 1ns/1ps

module spi_sva (
    // Top-level / APB / Regfile signals
    input wire        PCLK,
    input wire        PRESETn,
    input wire        PSEL,
    input wire        PENABLE,
    input wire        PREADY,
    input wire        PSLVERR,

    // Internal regfile signals needing tap
    input wire        ctrl_en,
    input wire [4:0]  int_stat,
    input wire [4:0]  int_en,
    input wire        IRQ,

    // Core signals needing tap
    input wire        sclk,
    input wire        mosi,
    input wire        cpol,
    input wire        cpha,
    input wire [3:0]  ss_n
);

    // Instantiate Regfile Assertions
    spi_regfile_sva u_regfile_sva (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .IRQ(IRQ),
        .ctrl_en(ctrl_en),
        .INT_STAT(int_stat),
        .INT_EN(int_en)
    );

    // Instantiate Core Assertions
    spi_core_sva u_core_sva (
        .clk(PCLK),       // Assuming PCLK drives the core
        .rst_n(PRESETn),  // Assuming PRESETn drives the core
        .sclk(sclk),
        .mosi(mosi),
        .cpol(cpol),
        .cpha(cpha),
        .ss_n(ss_n)
    );

endmodule

`endif // SPI_SVA_SV
