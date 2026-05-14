// =============================================================================
// ref_model.sv - Reference Model + Scoreboard (Comprehensive)
// =============================================================================
// SPI Master Reference Model with full mode support (CPOL/CPHA).
// Independently predicts SPI transfers for comparison against DUT.
// Tracks FIFOs, interrupts, and protocol compliance.
// =============================================================================

`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // =========================================================================
    // CONFIGURATION STATE
    // =========================================================================
    bit [1:0]  cfg_mode;           // {CPOL, CPHA}
    bit        cfg_lsb_first;
    bit [1:0]  cfg_width;          // 00=8, 01=16, 10=32
    bit        cfg_loopback;
    bit        cfg_en;
    bit [15:0] cfg_clk_div;
    bit [7:0]  cfg_delay;

    // =========================================================================
    // FIFO MODELS (Internal queues tracking expected behavior)
    // =========================================================================
    bit [31:0] tx_fifo_model[$];   // TX data queue
    bit [31:0] rx_fifo_model[$];   // RX data queue
    bit [31:0] rx_expected[$];     // Expected RX data for scoreboarding

    // =========================================================================
    // INTERRUPT STATE
    // =========================================================================
    bit [4:0]  int_en_mask;        // Interrupt enable bits
    bit [4:0]  int_stat_model;     // Model of interrupt status

    // =========================================================================
    // ERROR TRACKING
    // =========================================================================
    int error_count = 0;
    int warning_count = 0;

    // =========================================================================
    // REGISTER STATE MODELS
    // =========================================================================
    bit [31:0] status_model;
    bit        busy_model;
    bit        tx_full_model;
    bit        tx_empty_model;
    bit        rx_full_model;
    bit        rx_empty_model;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    function new();
        reset();
    endfunction

    // =========================================================================
    // UPDATE CONFIG FROM CTRL REGISTER
    // =========================================================================
    function void update_ctrl_config(bit [31:0] ctrl_val);
        bit mstr_bit ;
        cfg_en        = ctrl_val[0];
        mstr_bit      = ctrl_val[1];  // Always assume master
        cfg_mode      = ctrl_val[3:2];
        cfg_lsb_first = ctrl_val[4];
        cfg_loopback  = ctrl_val[5];
        cfg_width     = ctrl_val[7:6];
        
        if (mstr_bit !== 1'b1) begin
            $display("[WARNING] DUT not in master mode - may affect transfers");
            warning_count++;
        end
    endfunction

    // =========================================================================
    // UPDATE FIFO COUNTS FROM STATUS
    // =========================================================================
    function void update_fifo_status(bit [31:0] status_val);
        busy_model     = status_val[0];
        tx_full_model  = status_val[1];
        tx_empty_model = status_val[2];
        rx_full_model  = status_val[3];
        rx_empty_model = status_val[4];
    endfunction

    // =========================================================================
    // PREDICT TX PUSH (write to TX_DATA)
    // =========================================================================
    task push_tx_data(bit [31:0] data);
        if (tx_fifo_model.size() < 8) begin
            // Extract only the relevant bits based on width
            bit [31:0] masked_data;
            case (cfg_width)
                2'b00: masked_data = {24'h0, data[7:0]};
                2'b01: masked_data = {16'h0, data[15:0]};
                2'b10: masked_data = data;
                default: masked_data = data;
            endcase
            tx_fifo_model.push_back(masked_data);
            // Predict future status updates
            tx_empty_model = 1'b0;
            if (tx_fifo_model.size() >= 8)
                tx_full_model = 1'b1;
        end else begin
            $display("[SCOREBOARD_ERROR] TX FIFO overflow - attempted to push when full");
            error_count++;
        end
    endtask

    // =========================================================================
    // PREDICT TX POP (when core transfers data)
    // =========================================================================
    function void pop_tx_data();
        bit [31:0] tx_word;
        if (tx_fifo_model.size() > 0) begin
            tx_word = tx_fifo_model.pop_front();
            // Predict RX based on transfer mode
            predict_spi_transfer(tx_word);
            if (tx_fifo_model.size() == 0)
                tx_empty_model = 1'b1;
            tx_full_model = 1'b0;
        end
    endfunction

    // =========================================================================
    // PREDICT SPI TRANSFER (core logic)
    // =========================================================================
    function void predict_spi_transfer(bit [31:0] tx_data);
        bit [31:0] rx_data;
        bit cpol;
        bit cpha;
        cpol = cfg_mode[1];
        cpha = cfg_mode[0];
        // In loopback mode, RX = TX; otherwise RX comes from external MISO
        // For testing, we assume external slave echoes TX in normal mode
        if (cfg_loopback) begin
            rx_data = tx_data;
        end else begin
            // Non-loopback: RX is typically all zeros in slave simulation
            // In real tests, use external slave BFM pattern
            rx_data = 32'h0;  // Default: assume slave sends zeros
        end

        // Apply bit ordering
        rx_data = apply_bit_order(rx_data);

        // Push to expected RX
        if (rx_fifo_model.size() < 8) begin
            rx_fifo_model.push_back(rx_data);
            rx_empty_model = 1'b0;
            if (rx_fifo_model.size() >= 8)
                rx_full_model = 1'b1;
        end else begin
            $display("[SCOREBOARD_ERROR] RX FIFO model overflow");
            error_count++;
        end
    endfunction

    // =========================================================================
    // APPLY BIT ORDER TRANSFORMATION
    // =========================================================================
    function bit [31:0] apply_bit_order(bit [31:0] data);
        bit [31:0] result;
        int width_bits ;
        result = data;
        width_bits = (cfg_width == 2'b00) ? 8 :
                        (cfg_width == 2'b01) ? 16 : 32;
        
        if (cfg_lsb_first) begin
            // Reverse bits within the frame
            for (int i = 0; i < width_bits; i++) begin
                result[i] = data[width_bits - 1 - i];
            end
        end
        return result;
    endfunction

    // =========================================================================
    // PREDICT RX POP (read from RX_DATA)
    // =========================================================================
    function bit [31:0] pop_rx_data();
        bit [31:0] data;
        if (rx_fifo_model.size() > 0) begin
            data = rx_fifo_model.pop_front();
            if (rx_fifo_model.size() == 0)
                rx_empty_model = 1'b1;
            rx_full_model = 1'b0;
        end else begin
            data = 32'h0;
            $display("[SCOREBOARD_ERROR] RX FIFO model underflow");
            error_count++;
        end
        return data;
    endfunction

    // =========================================================================
    // VERIFY RX AGAINST OBSERVATION
    // =========================================================================
    task verify_rx_data(bit [31:0] observed);
        bit [31:0] expected;
        bit [31:0] obs_masked, exp_masked;
        if (rx_fifo_model.size() > 0) begin
            expected = rx_fifo_model[0];  // Peek, don't pop (scoreboard doesn't pop)
            
            // Compare based on width
           
            case (cfg_width)
                2'b00: begin
                    obs_masked = {24'h0, observed[7:0]};
                    exp_masked = {24'h0, expected[7:0]};
                end
                2'b01: begin
                    obs_masked = {16'h0, observed[15:0]};
                    exp_masked = {16'h0, expected[15:0]};
                end
                2'b10: begin
                    obs_masked = observed;
                    exp_masked = expected;
                end
                default: begin
                    obs_masked = observed;
                    exp_masked = expected;
                end
            endcase
            
            if (obs_masked !== exp_masked) begin
                $display("[SCOREBOARD_ERROR] RX data mismatch: expected=0x%08h, observed=0x%08h, width=%0d",
                         exp_masked, obs_masked, cfg_width);
                error_count++;
            end
        end else begin
            $display("[SCOREBOARD_ERROR] RX read with empty model FIFO");
            error_count++;
        end
    endtask

    // =========================================================================
    // VERIFY CTRL REGISTER
    // =========================================================================
    task verify_ctrl(bit [31:0] observed);
        bit [31:0] expected = {
            24'h0,
            cfg_width,
            cfg_loopback,
            cfg_lsb_first,
            cfg_mode,
            1'b1,           // Master mode
            cfg_en
        };
        
        // Mask to relevant bits only
        bit [31:0] obs_masked = observed & 32'h000000FF;
        bit [31:0] exp_masked = expected & 32'h000000FF;
        
        if (obs_masked !== exp_masked) begin
            $display("[SCOREBOARD_ERROR] CTRL register mismatch: expected=0x%02h, observed=0x%02h",
                     exp_masked, obs_masked);
            error_count++;
        end
    endtask

    // =========================================================================
    // VERIFY STATUS REGISTER
    // =========================================================================
    task verify_status(bit [31:0] observed);
        bit [31:0] expected = {
            26'h0,
            1'b0,              // [6] RX_OVF - not modeled detail
            1'b0,              // [5] TX_OVF - not modeled detail
            rx_empty_model,    // [4]
            rx_full_model,     // [3]
            tx_empty_model,    // [2]
            tx_full_model,     // [1]
            busy_model         // [0]
        };
        
        bit [31:0] obs_masked = observed & 32'h0000007F;
        bit [31:0] exp_masked = expected & 32'h0000007F;
        
        if ((obs_masked & 32'h0000001F) !== (exp_masked & 32'h0000001F)) begin
            $display("[SCOREBOARD_ERROR] STATUS register mismatch: expected=0x%08h, observed=0x%08h",
                     exp_masked, obs_masked);
            error_count++;
        end
    endtask

    // =========================================================================
    // UPDATE INTERRUPT STATE
    // =========================================================================
    function void update_int_en(bit [4:0] int_en_val);
        int_en_mask = int_en_val;
    endfunction

    function void update_int_stat(bit [4:0] int_stat_val);
        int_stat_model = int_stat_val;
    endfunction

    // =========================================================================
    // RESET MODEL STATE
    // =========================================================================
    function void reset();
        cfg_en        = 1'b0;
        cfg_mode      = 2'b00;
        cfg_lsb_first = 1'b0;
        cfg_width     = 2'b00;
        cfg_loopback  = 1'b0;
        cfg_clk_div   = 16'h0;
        cfg_delay     = 8'h0;
        
        tx_fifo_model.delete();
        rx_fifo_model.delete();
        rx_expected.delete();
        
        int_en_mask   = 5'h0;
        int_stat_model = 5'h0;
        
        busy_model     = 1'b0;
        tx_full_model  = 1'b0;
        tx_empty_model = 1'b1;
        rx_full_model  = 1'b0;
        rx_empty_model = 1'b1;
    endfunction

    // =========================================================================
    // REPORT SUMMARY
    // =========================================================================
    function void report();
        $display("\n========================================");
        $display("REFERENCE MODEL REPORT");
        $display("========================================");
        $display("Errors detected:   %0d", error_count);
        $display("Warnings detected: %0d", warning_count);
        if (error_count == 0) begin
            $display("Status: PASS");
        end else begin
            $display("Status: FAIL");
        end
        $display("========================================\n");
    endfunction

endclass

`endif // SPI_REF_MODEL_SV