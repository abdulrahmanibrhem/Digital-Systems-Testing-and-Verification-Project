// =============================================================================
// reset_comprehensive_test.sv - Comprehensive Reset Verification Test
// =============================================================================
// Verifies reset behavior: register values, FIFO clearing, interrupt clearing,
// and protocol stability after reset sequences.
// =============================================================================

`ifndef RESET_COMPREHENSIVE_TEST_SV
`define RESET_COMPREHENSIVE_TEST_SV
import spi_env_pkg::*;
class reset_comprehensive_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        
        bit [31:0] rd;
        int error_count_start;

        $display("[INFO] reset_comprehensive_test: starting");
        error_count_start = ref_model.error_count;

        // =====================================================================
        // TEST 1: Verify reset default values
        // =====================================================================
        $display("[INFO] reset_comprehensive_test: TEST1 - Reset defaults");
        
        // Assume reset has already been applied by tb_top
        // Verify all registers are at their reset values
        
        tb_top.u_apb_bfm.apb_read(8'h00, rd);  // CTRL
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] CTRL after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h04, rd);  // STATUS
        // Bit[2] TX_EMPTY should be 1 (FIFO empty), Bit[4] RX_EMPTY should be 1
        if ((rd[2] != 1'b1) || (rd[4] != 1'b1)) begin
            $display("[SCOREBOARD_ERROR] STATUS after reset: TX/RX should be empty");
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h10, rd);  // CLK_DIV
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] CLK_DIV after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h14, rd);  // SS_CTRL
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] SS_CTRL after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h18, rd);  // INT_EN
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] INT_EN after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h1C, rd);  // INT_STAT
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] INT_STAT after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h20, rd);  // DELAY
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] DELAY after reset: expected 0x00000000, got 0x%08h", rd);
            ref_model.error_count++;
        end

        // =====================================================================
        // TEST 2: Write data, then reset, verify clearing
        // =====================================================================
        $display("[INFO] reset_comprehensive_test: TEST2 - Reset after activity");
        
        // Write configuration and data
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0021);  // Enable + LOOPBACK
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0020);  // CLK_DIV
        tb_top.u_apb_bfm.apb_write(8'h18, 32'h0000_001F);  // INT_EN all
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00CC);  // TX_DATA
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00DD);  // TX_DATA again
        
        // Push some RX data by performing transfer
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // SS_CTRL
        repeat(500) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0) break;
        end
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);  // Deassert SS

        // Verify data was transferred (FIFO has something)
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        $display("[INFO] STATUS before reset: 0x%08h", rd);

        // Now apply reset
        $display("[INFO] Applying PRESETn=0");
        tb_top.PRESETn = 0;
        #100;
        tb_top.PRESETn = 1;
        #100;

        // Verify reset clears all state
        tb_top.u_apb_bfm.apb_read(8'h00, rd);  // CTRL
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] CTRL not cleared by reset");
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h04, rd);  // STATUS
        if ((rd[2] != 1'b1) || (rd[4] != 1'b1) || rd[0] != 1'b0) begin
            $display("[SCOREBOARD_ERROR] STATUS not reset to default: 0x%08h", rd);
            ref_model.error_count++;
        end

        tb_top.u_apb_bfm.apb_read(8'h1C, rd);  // INT_STAT
        if (rd != 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] INT_STAT not cleared by reset");
            ref_model.error_count++;
        end

        // =====================================================================
        // TEST 3: Normal operation after reset
        // =====================================================================
        $display("[INFO] reset_comprehensive_test: TEST3 - Operation after reset");
        
        ref_model.reset();  // Reset model state too
        
        // Perform basic transfer
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0021);  // Enable + LOOPBACK
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0010);  // CLK_DIV
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // SS_CTRL
        
        ref_model.update_ctrl_config(32'h0000_0021);
        coverage.sample_config(2'b00, 1'b0, 2'b00);

        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00EE);  // TX_DATA
        ref_model.push_tx_data(32'h000000EE);

        repeat(500) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0) break;
        end

        tb_top.u_apb_bfm.apb_read(8'h0C, rd);  // RX_DATA
        ref_model.verify_rx_data(rd);

        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);  // Deassert SS

        // =====================================================================
        // TEST 4: Multiple reset cycles
        // =====================================================================
        $display("[INFO] reset_comprehensive_test: TEST4 - Multiple reset cycles");
        
        for (int cycle = 0; cycle < 3; cycle++) begin
            $display("[INFO] Reset cycle %0d", cycle + 1);
            
            tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0001);  // Enable
            tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0008);  // CLK_DIV
            #50;
            
            // Reset
            tb_top.PRESETn = 0;
            #100;
            tb_top.PRESETn = 1;
            #100;
            
            // Verify reset
            tb_top.u_apb_bfm.apb_read(8'h00, rd);
            if (rd != 32'h0000_0000) begin
                $display("[SCOREBOARD_ERROR] CTRL not reset in cycle %0d", cycle + 1);
                ref_model.error_count++;
            end
        end

        // =====================================================================
        // FINAL: Report
        // =====================================================================
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);  // Final disable

        if (ref_model.error_count == error_count_start) begin
            $display("[TEST_PASSED] reset_comprehensive_test");
        end else begin
            $display("[TEST_FAILED] reset_comprehensive_test: errors=%0d",
                     ref_model.error_count - error_count_start);
        end

    endtask

endclass

`endif // RESET_COMPREHENSIVE_TEST_SV
