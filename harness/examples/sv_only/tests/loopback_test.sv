// loopback_test.sv — STUB (Owner: M6)
// Purpose: LOOPBACK=1, MISO=nonsense, verify RX==TX (R19)
`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
class loopback_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        $display("[INFO] loopback_test: TODO — not yet implemented");
    endtask
endclass
`endif
