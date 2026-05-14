# tests/

This folder contains all test programs. Each test targets a specific aspect
of the DUT's behavior. Tests are selected at runtime using the +TESTNAME plusarg.

Files:
    ral_hw_reset_test.sv
    reset_comprehensive_test.sv
    fifo_stress_test.sv
    interrupt_test.sv
    mode_cross_test.sv

description : 
🔷 Test Organization (Correct Version)

Verification scenarios are implemented as directed SystemVerilog tests located in the tests/ directory.

Each test exercises a specific SPI behavior or corner case while interacting with a shared verification environment located in the env/ directory.

The environment provides reference modeling and functional coverage, while tests focus purely on stimulus generation and scenario control.

🔷 Separation of Responsibilities
env/ → contains reusable verification components (reference model, coverage, shared utilities)
tests/ → contains directed test scenarios targeting specific functional behaviors of the SPI design

This separation ensures that stimulus logic is isolated from verification intelligence, improving maintainability and debugging efficiency.
//later


