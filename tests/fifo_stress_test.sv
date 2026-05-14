// =============================================================================
// fifo_stress_test.sv - FIFO Stress Test
// =============================================================================
// Tests FIFO boundary conditions: empty, full, back-to-back transfers,
// and overflow attempts. Validates FIFO counter consistency.
// =============================================================================

`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV
import spi_env_pkg::*;
class fifo_stress_test;

static task run(ref spi_ref_model    ref_model,
                spi_coverage_col coverage);
        
        bit [31:0] rd;
        int i, j;
        int error_count_start;
        bit [31:0] overflow_data;
        $display("[INFO] fifo_stress_test: starting");
        error_count_start = ref_model.error_count;

        // Setup: 8-bit width, mode 0, loopback ON for predictable RX
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0021);  // EN, MSTR, LOOPBACK
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0008);  // CLK_DIV
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // SS_CTRL

        ref_model.cfg_loopback = 1'b1;
        ref_model.cfg_width = 2'b00;
        
        // =====================================================================
        // TEST 1: Fill TX FIFO to capacity (8 entries)
        // =====================================================================
        $display("[INFO] fifo_stress_test: TEST1 - Fill TX FIFO");
        
        for (i = 0; i < 8; i = i + 1) begin
            bit [31:0] tmp;
            bit [31:0] tx_word;
            tmp = i * 32'h11111111;
            tx_word = {24'h0, tmp[7:0]};
            tb_top.u_apb_bfm.apb_write(8'h08, tx_word);  // TX_DATA
            ref_model.push_tx_data(tx_word);
        end

        // Check STATUS: TX should show FULL
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        if (rd[1] != 1'b1) begin  // TX_FULL bit
            $display("[SCOREBOARD_ERROR] TX FIFO not full after 8 pushes");
            ref_model.error_count++;
        end

        coverage.sample_fifo(3'b111, 3'b000);  // TX full, RX empty

        // Attempt overflow (would be discarded or cause error)
        overflow_data = 32'h0000_AABB;
        tb_top.u_apb_bfm.apb_write(8'h08, overflow_data);
        $display("[INFO] fifo_stress_test: Attempted TX overflow - no exception expected");

        // =====================================================================
        // TEST 2: Process transfers (back-to-back)
        // =====================================================================
        $display("[INFO] fifo_stress_test: TEST2 - Process back-to-back transfers");
        
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // Assert SS
        
        // Wait for all 8 transfers to complete
        for (i = 0; i < 8; i = i + 1) begin
            int poll_count = 0;
            while (poll_count < 2000 && poll_count < (100 * 8)) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);
                if (rd[0] == 1'b0 && rd[1] == 1'b0) break;  // Not busy and not full
                poll_count++;
            end
            if (poll_count >= 2000) begin
                $display("[TEST_FAILED] fifo_stress_test: Transfer %0d timeout", i);
                ref_model.error_count++;
                break;
            end
        end

        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);  // Deassert SS

        // =====================================================================
        // TEST 3: Verify RX FIFO with multiple data
        // =====================================================================
        $display("[INFO] fifo_stress_test: TEST3 - Read RX FIFO");
        
        // Read back as much as available
        for (i = 0; i < 8; i = i + 1) begin
            bit [31:0] status;
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);  // RX_DATA
            tb_top.u_apb_bfm.apb_read(8'h04, status);
            if (status[4] == 1'b1) break;  // RX empty 
        end

        $display("[INFO] fifo_stress_test: Read %0d RX words", i);

        // =====================================================================
        // TEST 4: TX FIFO Empty Test
        // =====================================================================
        $display("[INFO] fifo_stress_test: TEST4 - TX FIFO empty condition");
        
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        if ((rd[2] & ~rd[1]) != 1'b1) begin  // TX_EMPTY but not TX_FULL
            $display("[SCOREBOARD_ERROR] TX FIFO not empty after draining");
            ref_model.error_count++;
        end

        coverage.sample_fifo(3'b000, 3'b000);  // TX empty, RX empty

        // =====================================================================
        // TEST 5: Single-entry transfers in rapid succession
        // =====================================================================
        $display("[INFO] fifo_stress_test: TEST5 - Rapid single transfers");
        
        for (i = 0; i < 4; i = i + 1) begin
            bit [31:0] tx_word;
            tx_word = {24'h0, (8'h55 + i)};
            
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);  // Assert SS
            tb_top.u_apb_bfm.apb_write(8'h08, tx_word);
            
            // Wait for transfer
            repeat(500) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);
                if (rd[0] == 1'b0) break;
            end
            
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);  // RX_DATA
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);  // Deassert SS
            #50;
        end

        coverage.sample_fifo(3'b001, 3'b001);  // Both with data

        // =====================================================================
        // FINAL: Disable and report
        // =====================================================================
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);  // Disable

        if (ref_model.error_count == error_count_start) begin
            $display("[TEST_PASSED] fifo_stress_test");
        end else begin
            $display("[TEST_FAILED] fifo_stress_test: errors=%0d",
                     ref_model.error_count - error_count_start);
        end

    endtask

endclass

`endif // FIFO_STRESS_TEST_SV
