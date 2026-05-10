// interrupt_test.sv — STUB (Owner: M7)
// Purpose: 5 interrupts — trigger, mask, W1C, W1C race (R16, R17, R18)
`ifndef INTERRUPT_TEST_SV
`define INTERRUPT_TEST_SV
`include "../env/ref_model.sv"
`include "../env/coverage.sv"
class interrupt_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        $display("[INFO] interrupt_test: TODO — not yet implemented");
    endtask
endclass
`endif
