`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // =========================================================================
    // CONFIGURATION STATE
    // =========================================================================
    bit [1:0]  cfg_mode;           // {CPOL, CPHA}
    bit        cfg_lsb_first;
    bit [1:0]  cfg_width;          // 00=8, 01=16, 10=32, 11=reserved
    bit        cfg_loopback;
    bit        cfg_en;
    bit        cfg_mstr;
    bit [15:0] cfg_clk_div;
    bit [7:0]  cfg_delay;

    // =========================================================================
    // RAW REGISTER STORAGE
    // =========================================================================
    bit [31:0] reg_ctrl;
    bit [31:0] reg_clk_div;
    bit [31:0] reg_ss_ctrl;
    bit [31:0] reg_int_en;
    bit [31:0] reg_delay;

    // =========================================================================
    // FIFO MODELS
    // =========================================================================
    bit [31:0] tx_fifo_model[$];
    bit [31:0] rx_fifo_model[$];
    bit [31:0] rx_expected[$];

    // =========================================================================
    // INTERRUPT STATE
    // =========================================================================
    bit [4:0] int_en_mask;
    bit [4:0] int_stat_model;

    // =========================================================================
    // STATUS / ERROR STATE
    // =========================================================================
    int error_count = 0;
    int warning_count = 0;

    bit [31:0] status_model;
    bit        busy_model;
    bit        tx_full_model;
    bit        tx_empty_model;
    bit        rx_full_model;
    bit        rx_empty_model;

    bit        tx_ovf;
    bit        rx_ovf;

    // =========================================================================
    // MOSI CHECK STATE
    // =========================================================================
    bit [31:0] last_tx_word;
    bit        last_tx_valid;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    function new();
        error_count   = 0;
        warning_count = 0;
        reset();
    endfunction

    // =========================================================================
    // RESET MODEL STATE
    // =========================================================================
    function void reset();
        cfg_en        = 1'b0;
        cfg_mstr      = 1'b0;
        cfg_mode      = 2'b00;
        cfg_lsb_first = 1'b0;
        cfg_width     = 2'b11;       // sentinel: not configured
        cfg_loopback  = 1'b0;
        cfg_clk_div   = 16'h0000;
        cfg_delay     = 8'h00;

        reg_ctrl      = 32'h0000_0000;
        reg_clk_div   = 32'h0000_0000;
        reg_ss_ctrl   = 32'h0000_0000;
        reg_int_en    = 32'h0000_0000;
        reg_delay     = 32'h0000_0000;

        tx_fifo_model.delete();
        rx_fifo_model.delete();
        rx_expected.delete();

        int_en_mask    = 5'h00;
        int_stat_model = 5'h00;

        busy_model     = 1'b0;
        tx_full_model  = 1'b0;
        tx_empty_model = 1'b1;
        rx_full_model  = 1'b0;
        rx_empty_model = 1'b1;

        tx_ovf         = 1'b0;
        rx_ovf         = 1'b0;
        last_tx_word   = 32'h0;
        last_tx_valid  = 1'b0;
    endfunction

    function void do_reset();
        reset();
        $display("[REF_MODEL] Reset applied - FIFOs flushed, config cleared");
    endfunction

    // =========================================================================
    // CONFIGURATION FUNCTIONS
    // =========================================================================
    function void update_ctrl_config(bit [31:0] ctrl_val);
        reg_ctrl      = ctrl_val & 32'h0000_00FF;

        cfg_en        = ctrl_val[0];
        cfg_mstr      = ctrl_val[1];
        cfg_mode      = ctrl_val[3:2];
        cfg_lsb_first = ctrl_val[4];
        cfg_loopback  = ctrl_val[5];
        cfg_width     = ctrl_val[7:6];

        if (!cfg_en) begin
            tx_fifo_model.delete();
            rx_fifo_model.delete();
            tx_empty_model = 1'b1;
            rx_empty_model = 1'b1;
            tx_full_model  = 1'b0;
            rx_full_model  = 1'b0;
            $display("[REF_MODEL] CTRL.EN=0 - FIFOs flushed");
        end

        if (cfg_mstr !== 1'b1) begin
            $display("[WARNING] DUT not in master mode - may affect transfers");
            warning_count++;
        end

        if (cfg_width == 2'b11) begin
            $display("[REF_MODEL_ERROR] CTRL.WIDTH=2'b11 is reserved");
            error_count++;
        end
    endfunction

    function void cfg_ctrl(input bit [31:0] val);
        update_ctrl_config(val);
    endfunction

    function void cfg_clk_div_reg(input bit [31:0] val);
        reg_clk_div = val & 32'h0000_FFFF;
        cfg_clk_div = val[15:0];
    endfunction

    function void cfg_ss_ctrl(input bit [31:0] val);
        reg_ss_ctrl = val & 32'h0000_00FF;
    endfunction

    function void cfg_delay_reg(input bit [31:0] val);
        reg_delay = val & 32'h0000_00FF;
        cfg_delay = val[7:0];
    endfunction

    function void cfg_int_en_reg(input bit [31:0] val);
        reg_int_en  = val & 32'h0000_001F;
        int_en_mask = val[4:0];
    endfunction

    function void update_int_en(bit [4:0] int_en_val);
        int_en_mask = int_en_val;
        reg_int_en  = {27'h0, int_en_val};
    endfunction

    function void update_int_stat(bit [4:0] int_stat_val);
        int_stat_model = int_stat_val;
    endfunction

    function void write_int_stat(input bit [31:0] wdata);
        int_stat_model = int_stat_model & ~(wdata[4:0]);
    endfunction

    // =========================================================================
    // FIFO STATUS UPDATE FROM DUT STATUS
    // =========================================================================
    function void update_fifo_status(bit [31:0] status_val);
        busy_model     = status_val[0];
        tx_full_model  = status_val[1];
        tx_empty_model = status_val[2];
        rx_full_model  = status_val[3];
        rx_empty_model = status_val[4];
        tx_ovf         = status_val[5];
        rx_ovf         = status_val[6];
    endfunction

    // =========================================================================
    // TX FIFO PUSH
    // =========================================================================
    task push_tx_data(bit [31:0] data);
        bit [31:0] masked_data;

        if (!cfg_en) begin
            $display("[REF_MODEL] push_tx_data ignored - CTRL.EN=0");
            return;
        end

        if (cfg_width == 2'b11) begin
            $display("[REF_MODEL_ERROR] push_tx_data: width not configured");
            error_count++;
            return;
        end

        if (tx_fifo_model.size() >= 8) begin
            tx_ovf = 1'b1;
            int_stat_model[2] = 1'b1;
            $display("[SCOREBOARD_ERROR] TX FIFO overflow - word 0x%08h discarded", data);
            error_count++;
            return;
        end

        masked_data = mask_by_width(data);
        tx_fifo_model.push_back(masked_data);

        tx_empty_model = 1'b0;
        tx_full_model  = (tx_fifo_model.size() >= 8);

        $display("[REF_MODEL] TX push 0x%08h - fifo depth now %0d",
                 masked_data, tx_fifo_model.size());
    endtask

    // =========================================================================
    // TRANSFER MODEL
    // =========================================================================
    function void pop_tx_data();
        if (tx_fifo_model.size() > 0) begin
            predict_spi_transfer(tx_fifo_model.pop_front());
            tx_empty_model = (tx_fifo_model.size() == 0);
            tx_full_model  = 1'b0;
        end
    endfunction

    function void predict_spi_transfer(bit [31:0] tx_data);
        bit [31:0] rx_data;

        if (cfg_loopback)
            rx_data = tx_data;
        else
            rx_data = 32'h0;

        rx_data = apply_bit_order(mask_by_width(rx_data));
        push_rx_prediction(rx_data);
    endfunction

    function void do_transfer(input bit [31:0] miso_pattern);
        bit [31:0] tx_word;
        bit [31:0] rx_word;
        int        width_bits;

        if (cfg_width == 2'b11) begin
            $display("[REF_MODEL_ERROR] do_transfer: width not configured");
            error_count++;
            return;
        end

        if (!cfg_en) begin
            $display("[REF_MODEL_ERROR] do_transfer: EN=0, no transfer should occur");
            error_count++;
            return;
        end

        if (!cfg_mstr) begin
            $display("[REF_MODEL_ERROR] do_transfer: MSTR=0, not in master mode");
            error_count++;
            return;
        end

        if (tx_fifo_model.size() == 0) begin
            $display("[REF_MODEL_ERROR] do_transfer: TX FIFO empty, no transfer expected");
            error_count++;
            return;
        end

        tx_word       = tx_fifo_model.pop_front();
        last_tx_word  = tx_word;
        last_tx_valid = 1'b1;

        width_bits = get_width_bits();

        if (cfg_loopback)
            rx_word = mask_by_width(tx_word);
        else
            rx_word = mask_by_width(miso_pattern);

        if (cfg_lsb_first)
            rx_word = bit_reverse(rx_word, width_bits);

        push_rx_prediction(rx_word);

        tx_empty_model = (tx_fifo_model.size() == 0);
        tx_full_model  = 1'b0;

        int_stat_model[4] = 1'b1;              // TRANSFER_DONE
        if (tx_fifo_model.size() == 0)
            int_stat_model[0] = 1'b1;          // TX_EMPTY
        if (rx_fifo_model.size() == 8)
            int_stat_model[1] = 1'b1;          // RX_FULL
    endfunction

    function void push_rx_prediction(bit [31:0] rx_data);
        if (rx_fifo_model.size() >= 8) begin
            rx_ovf = 1'b1;
            int_stat_model[3] = 1'b1;
            $display("[SCOREBOARD_ERROR] RX FIFO model overflow - word 0x%08h dropped", rx_data);
            error_count++;
        end else begin
            rx_fifo_model.push_back(rx_data);
            rx_empty_model = 1'b0;
            rx_full_model  = (rx_fifo_model.size() >= 8);
        end
    endfunction

    // =========================================================================
    // RX FIFO POP / CHECK
    // =========================================================================
    function bit [31:0] pop_rx_data();
        bit [31:0] data;

        if (rx_fifo_model.size() > 0) begin
            data = rx_fifo_model.pop_front();
            rx_empty_model = (rx_fifo_model.size() == 0);
            rx_full_model  = 1'b0;
        end else begin
            data = 32'h0;
            $display("[SCOREBOARD_ERROR] RX FIFO model underflow");
            error_count++;
        end

        return data;
    endfunction

    task verify_rx_data(bit [31:0] observed);
        check_rx_word(observed);
    endtask

    task check_rx_word(input bit [31:0] observed);
        bit [31:0] expected;

        if (rx_fifo_model.size() == 0) begin
            if (observed !== 32'h0) begin
                $display("[SCOREBOARD_ERROR] RX read while empty: expected=0x00000000 observed=0x%08h",
                         observed);
                error_count++;
            end else begin
                $display("[SCOREBOARD_PASS] RX empty read correct: 0x00000000");
            end
            return;
        end

        expected = rx_fifo_model.pop_front();

        rx_empty_model = (rx_fifo_model.size() == 0);
        rx_full_model  = 1'b0;

        if (mask_by_width(observed) !== mask_by_width(expected)) begin
            $display("[SCOREBOARD_ERROR] RX word mismatch: expected=0x%08h observed=0x%08h",
                     mask_by_width(expected), mask_by_width(observed));
            error_count++;
        end else begin
            $display("[SCOREBOARD_PASS] RX word match: 0x%08h", observed);
        end
    endtask

    // =========================================================================
    // MOSI CHECK
    // =========================================================================
    task check_tx_mosi(input bit [31:0] captured_mosi);
        bit [31:0] expected_mosi;
        bit [31:0] mask;
        int        width_bits;

        if (!last_tx_valid) begin
            $display("[REF_MODEL_ERROR] check_tx_mosi called before any transfer");
            error_count++;
            return;
        end

        mask       = get_width_mask();
        width_bits = get_width_bits();

        if (cfg_lsb_first)
            expected_mosi = bit_reverse(last_tx_word & mask, width_bits);
        else
            expected_mosi = last_tx_word & mask;

        if ((captured_mosi & mask) !== expected_mosi) begin
            $display("[SCOREBOARD_ERROR] MOSI mismatch: expected=0x%08h observed=0x%08h",
                     expected_mosi, captured_mosi & mask);
            error_count++;
        end else begin
            $display("[SCOREBOARD_PASS] MOSI match: 0x%08h", expected_mosi);
        end
    endtask

    // =========================================================================
    // REGISTER CHECKS
    // =========================================================================
    task verify_ctrl(bit [31:0] observed);
        check_ctrl(observed);
    endtask

    task check_reg(input string name,
                   input bit [31:0] expected,
                   input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            error_count++;
        end else begin
            $display("[SCOREBOARD_PASS] %s match: 0x%08h", name, observed);
        end
    endtask

    task check_ctrl(input bit [31:0] observed);
        check_reg("CTRL", reg_ctrl, observed & 32'h0000_00FF);
    endtask

    task check_clk_div(input bit [31:0] observed);
        check_reg("CLK_DIV", reg_clk_div, observed & 32'h0000_FFFF);
    endtask

    task check_ss_ctrl(input bit [31:0] observed);
        check_reg("SS_CTRL", reg_ss_ctrl, observed & 32'h0000_00FF);
    endtask

    task check_int_en(input bit [31:0] observed);
        check_reg("INT_EN", reg_int_en, observed & 32'h0000_001F);
    endtask

    task check_delay(input bit [31:0] observed);
        check_reg("DELAY", reg_delay, observed & 32'h0000_00FF);
    endtask

    // =========================================================================
    // STATUS / IRQ CHECKS
    // =========================================================================
    task verify_status(bit [31:0] observed);
        check_status(observed, busy_model);
    endtask

    task check_status(input bit [31:0] observed, input bit busy);
        bit [31:0] expected;

        expected = predict_status(busy);

        if ((observed & 32'h0000_007F) !== expected) begin
            $display("[SCOREBOARD_ERROR] STATUS mismatch: expected=0x%08h observed=0x%08h",
                     expected, observed & 32'h0000_007F);
            error_count++;
        end
    endtask

    task check_irq(input bit observed_irq);
        bit expected;

        expected = predict_irq();

        if (observed_irq !== expected) begin
            $display("[SCOREBOARD_ERROR] IRQ mismatch: expected=%0b observed=%0b",
                     expected, observed_irq);
            error_count++;
        end
    endtask

    function bit [31:0] predict_status(input bit busy);
        bit [31:0] s;

        s = 32'h0;
        s[0] = busy;
        s[1] = (tx_fifo_model.size() == 8);
        s[2] = (tx_fifo_model.size() == 0);
        s[3] = (rx_fifo_model.size() == 8);
        s[4] = (rx_fifo_model.size() == 0);
        s[5] = tx_ovf;
        s[6] = rx_ovf;

        return s;
    endfunction

    function bit predict_irq();
        return |(int_stat_model & int_en_mask);
    endfunction

    // =========================================================================
    // HELPERS
    // =========================================================================
    function bit [31:0] apply_bit_order(bit [31:0] data);
        if (cfg_lsb_first)
            return bit_reverse(data, get_width_bits());
        else
            return data;
    endfunction

    function bit [31:0] mask_by_width(input bit [31:0] data);
        return data & get_width_mask();
    endfunction

    function bit [31:0] get_width_mask();
        case (cfg_width)
            2'b00: return 32'h0000_00FF;
            2'b01: return 32'h0000_FFFF;
            2'b10: return 32'hFFFF_FFFF;
            default: return 32'h0000_00FF;
        endcase
    endfunction

    function int get_width_bits();
        case (cfg_width)
            2'b00: return 8;
            2'b01: return 16;
            2'b10: return 32;
            default: return 8;
        endcase
    endfunction

    function automatic bit [31:0] bit_reverse(input bit [31:0] data,
                                               input int width);
        bit [31:0] result;

        result = 32'h0;

        for (int i = 0; i < width; i++)
            result[i] = data[width - 1 - i];

        return result;
    endfunction

    function int delay_in_pclk();
        return int'(cfg_delay) * (int'(cfg_clk_div) + 1);
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

        if (error_count == 0)
            $display("Status: PASS");
        else
            $display("Status: FAIL");

        $display("========================================\n");
    endfunction

endclass

`endif // SPI_REF_MODEL_SV
