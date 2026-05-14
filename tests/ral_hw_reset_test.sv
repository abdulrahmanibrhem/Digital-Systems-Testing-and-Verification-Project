// =============================================================================
// ral_hw_reset_test.sv
// -----------------------------------------------------------------------------
// RAL bonus test - SV-only scaffold does not implement UVM RAL
// This is a stub that prints TEST_SKIPPED
// =============================================================================

`ifndef RAL_HW_RESET_TEST_SV
`define RAL_HW_RESET_TEST_SV
import spi_env_pkg::*;
class ral_hw_reset_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        
        $display("[TEST_SKIPPED] ral_hw_reset_test");
        // SV-only scaffold does not implement UVM RAL
        // Students attempting the RAL bonus would replace this with
        // a full UVM-based test that uses uvm_reg_block
    endtask

endclass

`endif // RAL_HW_RESET_TEST_SV