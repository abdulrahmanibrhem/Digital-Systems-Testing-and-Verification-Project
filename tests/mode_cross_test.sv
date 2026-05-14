// =============================================================================
// mode_cross_test.sv - SPI Mode Crossover Test
// =============================================================================
// Tests all 4 SPI modes (CPOL/CPHA combinations) with various frame sizes.
// Validates mode-specific timing behavior and bit sampling.
// =============================================================================

`ifndef MODE_CROSS_TEST_SV
`define MODE_CROSS_TEST_SV
import spi_env_pkg::*;
class mode_cross_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        
        bit [1:0] mode, width;
        bit [31:0] ctrl_val;
        bit [31:0] test_data[4] = {32'hAAAAAAAA, 32'h55555555, 32'hF0F0F0F0, 32'h0F0F0F0F};
        int mode_idx, width_idx, data_idx;
        int error_count_start;

        $display("[INFO] mode_cross_test: starting");
        error_count_start = ref_model.error_count;

        // Iterate through all SPI modes (2'b00 to 2'b11)
        for (mode = 2'b00; mode < 4; mode = mode + 1) begin
            // Iterate through all frame widths (8, 16, 32 bits)
            for (width = 2'b00; width < 3; width = width + 1) begin
                
                $display("[INFO] Testing mode=%b (CPOL=%0b CPHA=%0b) width=%0d bits",
                         mode, mode[1], mode[0], 
                         (width == 2'b00) ? 8 : (width == 2'b01) ? 16 : 32);

                // Initialize DUT with current mode and width
                tb_top.bfm_mode = mode;
                
                ctrl_val = {
                    24'h0,
                    width,          // [7:6]
                    1'b0,           // [5] loopback OFF
                    1'b0,           // [4] MSB-first
                    mode,           // [3:2] SPI mode
                    1'b1,           // [1] master
                    1'b1            // [0] enable
                };
                
                tb_top.u_apb_bfm.apb_write(8'h00, ctrl_val);  // CTRL
                tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0010);  // CLK_DIV = 16
                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // SS_CTRL enable[0]
                
                // Update reference model
                ref_model.update_ctrl_config(ctrl_val);
                ref_model.cfg_width = width;
                
                // Sample coverage
                coverage.sample_config(mode, 1'b0, width);

                // Send 2 test patterns in sequence
                for (data_idx = 0; data_idx < 2; data_idx = data_idx + 1) begin
                    bit [31:0] tx_word = test_data[data_idx];
                    bit [31:0] rd;
                    int poll_count = 0;

                    ref_model.push_tx_data(tx_word);
                    tb_top.u_apb_bfm.apb_write(8'h08, tx_word);  // TX_DATA

                    // Wait for transfer complete (max 1000 cycles)
                    while (poll_count < 1000) begin
                        bit [31:0] status;
                        tb_top.u_apb_bfm.apb_read(8'h04, status);
                        if (status[0] == 1'b0) break;  // BUSY = 0
                        poll_count++;
                    end

                    if (poll_count >= 1000) begin
                        $display("[TEST_FAILED] mode_cross_test: Transfer timeout in mode %b width %0d",
                                 mode, width);
                        ref_model.error_count++;
                        continue;
                    end

                    // Verify RX (in loopback mode, RX = TX)
                    tb_top.u_apb_bfm.apb_read(8'h0C, rd);  // RX_DATA
                    ref_model.verify_rx_data(rd);
                end

                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);  // De-assert SS
                tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);  // Disable

                #100;  // Small delay between mode changes
            end
        end

        // Report results
        if (ref_model.error_count == error_count_start) begin
            $display("[TEST_PASSED] mode_cross_test");
        end else begin
            $display("[TEST_FAILED] mode_cross_test: errors=%0d",
                     ref_model.error_count - error_count_start);
        end

    endtask

endclass

`endif // MODE_CROSS_TEST_SV
