// error_injection_test.sv — STUB (Owner: M7)
// Purpose: TX write when full, RX read when empty, illegal width, reserved offsets (R13-R15, R23)
`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV
class error_injection_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        $display("[INFO] error_injection_test: TODO — not yet implemented");
    endtask
endclass
`endif
