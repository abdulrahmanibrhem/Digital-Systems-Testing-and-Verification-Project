// =============================================================================
// apb_master_bfm.sv  - APB Master BFM
// -----------------------------------------------------------------------------
// APB Master Bus Functional Model
// Drives APB transactions to configure the DUT
// =============================================================================

`ifndef APB_MASTER_BFM_SV
`define APB_MASTER_BFM_SV
`timescale 1ns/1ps

module apb_master_bfm (apb_if.master apb);

    // Register offsets
    localparam [7:0] CTRL     = 8'h00;
    localparam [7:0] STATUS   = 8'h04;
    localparam [7:0] TX_DATA  = 8'h08;
    localparam [7:0] RX_DATA  = 8'h0C;
    localparam [7:0] CLK_DIV  = 8'h10;
    localparam [7:0] SS_CTRL  = 8'h14;
    localparam [7:0] INT_EN   = 8'h18;
    localparam [7:0] INT_STAT = 8'h1C;
    localparam [7:0] DELAY    = 8'h20;

    initial begin
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= '0;
        apb.cb_master.pwdata  <= '0;
    end

    // -------------------------------------------------------------------------
    // APB Write transaction
    // -------------------------------------------------------------------------
    task automatic apb_write(input [7:0] addr, input [31:0] data);
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b1;
        apb.cb_master.paddr   <= addr;
        apb.cb_master.pwdata  <= data;
        @(apb.cb_master);
        apb.cb_master.penable <= 1'b1;
        do @(apb.cb_master); while (!apb.cb_master.pready);
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
    endtask


    task automatic apb_write_more_than_one_word (input [7:0] addr[], input [31:0] data [], input int count);
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b1;
        for (int i = 0; i < count; i++) begin
            apb.cb_master.penable <= 1'b0;
            apb.cb_master.pwrite  <= 1'b1;
            apb.cb_master.paddr   <= addr[i];
            apb.cb_master.pwdata  <= data[i];
            do @(apb.cb_master); while (!apb.cb_master.pready);
            apb.cb_master.penable <= 1'b0;
            @(apb.cb_master);
        end
        apb.cb_master.psel    <= 1'b0;
    endtask
    // -------------------------------------------------------------------------
    // APB Read transaction
    // -------------------------------------------------------------------------
    task automatic apb_read(input [7:0] addr, output [31:0] data);
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= addr;
        @(apb.cb_master);
        apb.cb_master.penable <= 1'b1;
        do @(apb.cb_master); while (!apb.cb_master.pready);
        data = apb.cb_master.prdata;
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
    endtask


    task automatic apb_read_more_than_one_word (input [7:0] addr[], output [31:0] data [], input int count);
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b1;
        for (int i = 0; i < count; i++) begin
            apb.cb_master.penable <= 1'b0;
            apb.cb_master.pwrite  <= 1'b0;
            apb.cb_master.paddr   <= addr[i];
            do @(apb.cb_master); while (!apb.cb_master.pready);
            data[i] = apb.cb_master.prdata;
            apb.cb_master.penable <= 1'b0;
            @(apb.cb_master);
        end
        apb.cb_master.psel    <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Convenience: Write CTRL register
    // -------------------------------------------------------------------------
    task automatic write_ctrl(input bit en, input bit mstr, 
                              input bit [1:0] mode, input bit lsb_first,
                              input bit loopback, input bit [1:0] width);
        bit [31:0] data = {
            24'b0,
            width,      // [7:6]
            loopback,   // [5]
            lsb_first,  // [4]
            mode,       // [3:2]
            mstr,       // [1]
            en          // [0]
        };
        apb_write(CTRL, data);
    endtask

    // -------------------------------------------------------------------------
    // Convenience: Enable DUT
    // -------------------------------------------------------------------------
    task automatic enable_dut(input bit [1:0] mode = 2'b00,
                              input bit lsb_first = 1'b0,
                              input bit [1:0] width = 2'b00);
        write_ctrl(1'b1, 1'b1, mode, lsb_first, 1'b0, width);
    endtask

    // -------------------------------------------------------------------------
    // Convenience: Disable DUT
    // -------------------------------------------------------------------------
    task automatic disable_dut();
        write_ctrl(1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 2'b00);
    endtask

    // =========================================================================
    // WRITE WITH VERIFICATION
    // =========================================================================
    task automatic apb_write_verify (
        input logic [7:0]  addr,
        input logic [31:0] data,
        output bit error
    );
        logic [31:0] rdata;
        error = 1'b0;
        apb_write(addr, data);
        apb_read(addr, rdata);
        if (rdata !== data) begin
            $display("[APB_BFM] VERIFY ERROR @%02h: wrote %08h, read %08h",
                     addr, data, rdata);
            error = 1'b1;
        end
    endtask

    // =========================================================================
    // BURST WRITE TASK
    // =========================================================================
    task automatic apb_burst_write (
        input logic [7:0]   base_addr,
        input logic [31:0]  data_list[],
        input int           count
    );
        int i;
        for (i = 0; i < count; i = i + 1) begin
            apb_write(base_addr + (i << 2), data_list[i]);
        end
    endtask

    // =========================================================================
    // BURST READ TASK
    // =========================================================================
    task automatic apb_burst_read (
        input logic [7:0]   base_addr,
        output logic [31:0] data_list[],
        input int           count
    );
        int i;
        for (i = 0; i < count; i = i + 1) begin
            apb_read(base_addr + (i << 2), data_list[i]);
        end
    endtask

    // =========================================================================
    // IDLE CYCLES
    // =========================================================================
    task automatic apb_idle (input int cycles);
        int i;
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        for (i = 0; i < cycles; i = i + 1)
            @(apb.cb_master);
    endtask

    // =========================================================================
    // WAIT FOR CONDITION WITH TIMEOUT
    // =========================================================================
    task automatic apb_wait_for_condition (
        input bit condition,
        input int timeout_cycles,
        output bit timeout_occurred
    );
        int cycle_count = 0;
        timeout_occurred = 1'b0;
        while (!condition && cycle_count < timeout_cycles) begin
            @(apb.cb_master);
            cycle_count = cycle_count + 1;
        end
        if (cycle_count >= timeout_cycles) begin
            timeout_occurred = 1'b1;
            $display("[APB_BFM] WARNING: Timeout waiting for condition after %0d cycles",
                     timeout_cycles);
        end
    endtask

    // =========================================================================
    // WRITE CLK_DIV
    // =========================================================================
    task automatic write_clk_div(input logic [15:0] div_value);
        apb_write(CLK_DIV, {16'b0, div_value});
    endtask

    // =========================================================================
    // WRITE SS_CTRL (slave select enable and value)
    // =========================================================================
    task automatic write_ss_ctrl(input logic [3:0] ss_enable, 
                                 input logic [3:0] ss_value);
        logic [31:0] data = {24'b0, ss_value, ss_enable};
        apb_write(SS_CTRL, data);
    endtask

    // =========================================================================
    // WRITE TX_DATA (push to FIFO)
    // =========================================================================
    task automatic write_tx_data(input logic [31:0] data);
        apb_write(TX_DATA, data);
    endtask

    // =========================================================================
    // READ RX_DATA (pop from FIFO)
    // =========================================================================
    task automatic read_rx_data(output logic [31:0] data);
        apb_read(RX_DATA, data);
    endtask

    // =========================================================================
    // READ STATUS
    // =========================================================================
    task automatic read_status(output logic [31:0] status);
        apb_read(STATUS, status);
    endtask

    // =========================================================================
    // CHECK STATUS - Verify specific status bits
    // =========================================================================
    task automatic check_status(
        input logic [7:0]  bit_mask,
        input logic [7:0]  expected,
        output bit         match
    );
        logic [31:0] status;
        logic [7:0]  actual;
        apb_read(STATUS, status);
        actual = status[7:0];
        match = (actual & bit_mask) == (expected & bit_mask);
        if (!match) begin
            $display("[APB_BFM] Status check FAILED: mask=%02h, expected=%02h, got=%02h",
                     bit_mask, expected, actual);
        end
    endtask

    // =========================================================================
    // INTERRUPT CONFIGURATION
    // =========================================================================
    task automatic write_int_en(input logic [4:0] int_mask);
        apb_write(INT_EN, {27'b0, int_mask});
    endtask

    task automatic read_int_stat(output logic [4:0] int_stat);
        logic [31:0] data;
        apb_read(INT_STAT, data);
        int_stat = data[4:0];
    endtask

    task automatic clear_int_stat(input logic [4:0] int_mask);
        apb_write(INT_STAT, {27'b0, int_mask});  // W1C
    endtask

    // =========================================================================
    // WRITE DELAY
    // =========================================================================
    task automatic write_delay(input logic [7:0] delay_val);
        apb_write(DELAY, {24'b0, delay_val});
    endtask

endmodule

`endif // APB_MASTER_BFM_SV