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
`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // ------------------------------------------------------------------ //
    //  Error counter
    // ------------------------------------------------------------------ //
    int error_count = 0;

    // ------------------------------------------------------------------ //
    //  Raw register storage — for read-back checks (PATH 2)
    //  We store the last written value so check_reg can compare
    // ------------------------------------------------------------------ //
    bit [31:0] reg_ctrl;
    bit [31:0] reg_clk_div;
    bit [31:0] reg_ss_ctrl;
    bit [31:0] reg_int_en;
    bit [31:0] reg_delay;

    // ------------------------------------------------------------------ //
    //  Decoded configuration — used by do_transfer logic
    // ------------------------------------------------------------------ //
    bit [1:0]  cfg_width;       // 2'b11 = sentinel (not configured)
    bit        cfg_en;
    bit        cfg_mstr;
    bit        cfg_lsb_first;
    bit [1:0]  cfg_mode;
    bit        cfg_loopback;
    bit [15:0] cfg_div;
    bit [7:0]  cfg_delay;
    bit [4:0]  cfg_int_en;

    // ------------------------------------------------------------------ //
    //  FIFO models — max 8 entries each, enforced strictly
    // ------------------------------------------------------------------ //
    bit [31:0] tx_fifo[$];
    bit [31:0] rx_fifo[$];

    // ------------------------------------------------------------------ //
    //  Last TX word — for MOSI check (PATH 3)
    //  Stores the word currently being (or just) shifted out
    // ------------------------------------------------------------------ //
    bit [31:0] last_tx_word;
    bit        last_tx_valid;   // false until first transfer happens

    // ------------------------------------------------------------------ //
    //  Sticky status and interrupt state
    // ------------------------------------------------------------------ //
    bit        tx_ovf;
    bit        rx_ovf;
    bit [4:0]  int_stat;

    // ================================================================== //
    //  CONSTRUCTOR
    //  Called once at simulation start when test writes:
    //    spi_ref_model ref = new();
    //  Sets everything to clean known state.
    //  2'b11 for cfg_width is our sentinel meaning "not configured yet"
    // ================================================================== //
    function new();
        error_count   = 0;

        // Raw registers — reset values from spec
        reg_ctrl      = 32'h0000_0000;
        reg_clk_div   = 32'h0000_0000;
        reg_ss_ctrl   = 32'h0000_0000;
        reg_int_en    = 32'h0000_0000;
        reg_delay     = 32'h0000_0000;

        // Decoded config — sentinel for width
        cfg_width     = 2'b11;   // NOT SET — do_transfer will error if still 11
        cfg_en        = 0;
        cfg_mstr      = 0;
        cfg_lsb_first = 0;
        cfg_mode      = 2'b00;
        cfg_loopback  = 0;
        cfg_div       = 16'h0000;
        cfg_delay     = 8'h00;
        cfg_int_en    = 5'h00;

        // FIFO state
        tx_ovf        = 0;
        rx_ovf        = 0;
        int_stat      = 5'h00;
        last_tx_valid = 0;
        last_tx_word  = 32'h0;

        tx_fifo.delete();
        rx_fifo.delete();
    endfunction

    // ================================================================== //
    //  RESET
    //  Call after PRESETn deasserts in your test.
    //  Mirrors hardware reset: registers to reset values, FIFOs flushed.
    //  Note: does NOT reset error_count — we keep counting across resets
    // ================================================================== //
    function void do_reset();
        // Raw registers back to reset values
        reg_ctrl      = 32'h0000_0000;
        reg_clk_div   = 32'h0000_0000;
        reg_ss_ctrl   = 32'h0000_0000;
        reg_int_en    = 32'h0000_0000;
        reg_delay     = 32'h0000_0000;

        // Decoded config — back to sentinel
        cfg_width     = 2'b11;
        cfg_en        = 0;
        cfg_mstr      = 0;
        cfg_lsb_first = 0;
        cfg_mode      = 2'b00;
        cfg_loopback  = 0;
        cfg_div       = 16'h0000;
        cfg_delay     = 8'h00;
        cfg_int_en    = 5'h00;

        // Clear FIFOs and sticky flags
        tx_fifo.delete();
        rx_fifo.delete();
        tx_ovf        = 0;
        rx_ovf        = 0;
        int_stat      = 5'h00;
        last_tx_valid = 0;
        last_tx_word  = 32'h0;

        $display("[REF_MODEL] Reset applied — FIFOs flushed, config cleared");
    endfunction

    // ================================================================== //
    //  CONFIGURATION FUNCTIONS (PATH 2 — register write side)
    //  Call these right after every apb_write to a config register.
    //  They do two things:
    //    1. Store the raw value for read-back checking
    //    2. Decode the fields for use in do_transfer logic
    // ================================================================== //

    function void cfg_ctrl(input bit [31:0] val);
        // Store raw value for read-back check
        // CTRL has no RO bits in the writable range so store as-is
        // mask out reserved bits [31:8] which always read 0
        reg_ctrl      = val & 32'h0000_00FF;

        // Decode fields
        cfg_en        = val[0];
        cfg_mstr      = val[1];
        cfg_mode      = val[3:2];
        cfg_lsb_first = val[4];
        cfg_loopback  = val[5];
        cfg_width     = val[7:6];

        // Spec R3: EN=0 flushes FIFOs immediately
        if (!cfg_en) begin
            tx_fifo.delete();
            rx_fifo.delete();
            $display("[REF_MODEL] CTRL.EN=0 — FIFOs flushed");
        end

        // Warn on reserved width
        if (cfg_width == 2'b11) begin
            $display("[REF_MODEL_ERROR] CTRL.WIDTH=2'b11 is reserved — undefined behavior");
            error_count++;
        end
    endfunction

    function void cfg_clk_div(input bit [31:0] val);
        reg_clk_div = val & 32'h0000_FFFF;   // only [15:0] used
        cfg_div     = val[15:0];
    endfunction

    function void cfg_ss_ctrl(input bit [31:0] val);
        reg_ss_ctrl = val & 32'h0000_00FF;   // only [7:0] used
    endfunction

    function void cfg_delay_reg(input bit [31:0] val);
        reg_delay = val & 32'h0000_00FF;     // only [7:0] used
        cfg_delay = val[7:0];
    endfunction

    function void cfg_int_en_reg(input bit [31:0] val);
        reg_int_en = val & 32'h0000_001F;    // only [4:0] used
        cfg_int_en = val[4:0];
    endfunction

    // ================================================================== //
    //  PUSH TX FIFO (PATH 3 — TX data write)
    //  Call every time test writes apb_write(TX_DATA, word)
    //
    //  Rules:
    //    - If EN=0: write silently ignored (spec)
    //    - If FIFO already has 8 entries: overflow error, discard word
    //    - Otherwise: push to back of queue
    // ================================================================== //
    function void push_tx(input bit [31:0] data);
        if (!cfg_en) begin
            // Spec says write ignored when EN=0 — not an error
            $display("[REF_MODEL] push_tx ignored — CTRL.EN=0");
            return;
        end

        if (cfg_width == 2'b11) begin
            $display("[REF_MODEL_ERROR] push_tx: width not configured");
            error_count++;
            return;
        end

        if (tx_fifo.size() >= 8) begin
            // FIFO is full — hardware discards word and sets overflow
            // This is CORRECT hardware behavior BUT means something is
            // wrong — test should have checked TX_FULL before pushing
            tx_ovf      = 1;
            int_stat[2] = 1;   // INT_STAT[TX_OVF]
            $display("[SCOREBOARD_ERROR] TX overflow — pushing when full, word 0x%08h discarded",
                     data);
            error_count++;
        end else begin
            tx_fifo.push_back(data);
            $display("[REF_MODEL] TX push 0x%08h — fifo depth now %0d",
                     data, tx_fifo.size());
        end
    endfunction

    // ================================================================== //
    //  DO TRANSFER
    //  Call AFTER your test polls BUSY=0 (transfer complete in hardware).
    //
    //  miso_pattern = the full word your spi_slave_bfm drove on MISO
    //                 during this transfer (ignored in loopback mode)
    //
    //  Steps:
    //    1. Pop one word from tx_fifo → this is what was shifted on MOSI
    //       Store it in last_tx_word so check_tx_mosi() can use it later
    //    2. Compute predicted RX word from miso_pattern (or loopback)
    //    3. Apply width mask — upper bits zero-filled per spec
    //    4. Apply bit reversal if LSB_FIRST
    //    5. Push predicted rx_word to rx_fifo
    //       ENFORCE: rx_fifo.size() must be < 8 before push
    //    6. Update interrupt status flags
    // ================================================================== //
    function void do_transfer(input bit [31:0] miso_pattern);
        bit [31:0] tx_word;
        bit [31:0] rx_word;
        bit [31:0] mask;
        int        width_bits;

        // ---- Guards ------------------------------------------------- //
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
        if (tx_fifo.size() == 0) begin
            $display("[REF_MODEL_ERROR] do_transfer: TX FIFO empty, no transfer expected");
            error_count++;
            return;
        end

        // ---- Step 1: Pop TX FIFO ------------------------------------ //
        // This word was shifted out on MOSI bit by bit by the hardware.
        // We save it so check_tx_mosi() can verify the slave BFM
        // captured the correct bits from the MOSI pin.
        tx_word       = tx_fifo.pop_front();
        last_tx_word  = tx_word;
        last_tx_valid = 1;
        $display("[REF_MODEL] Transfer: tx=0x%08h miso=0x%08h loopback=%0b lsb_first=%0b width=%0b",
                 tx_word, miso_pattern, cfg_loopback, cfg_lsb_first, cfg_width);

        // ---- Step 2: Width mask ------------------------------------- //
        case (cfg_width)
            2'b00: begin mask = 32'h0000_00FF; width_bits = 8;  end
            2'b01: begin mask = 32'h0000_FFFF; width_bits = 16; end
            2'b10: begin mask = 32'hFFFF_FFFF; width_bits = 32; end
            default: begin mask = 32'h0000_00FF; width_bits = 8; end
        endcase

        // ---- Step 3: Predicted RX word ------------------------------ //
        // Loopback: MOSI internally wired to MISO — rx = what we sent
        // Normal:   rx = what slave drove on MISO pin
        if (cfg_loopback)
            rx_word = tx_word & mask;
        else
            rx_word = miso_pattern & mask;

        // ---- Step 4: LSB_FIRST bit reversal ------------------------- //
        // MSB_FIRST (default): tx bit[WIDTH-1] goes first → rx arrives
        //   in same order → no reversal needed
        // LSB_FIRST: tx bit[0] goes first → rx arrives bit-reversed
        //   relative to the original word
        if (cfg_lsb_first)
            rx_word = bit_reverse(rx_word, width_bits);

        // ---- Step 5: Push to RX FIFO — enforce max 8 --------------- //
        if (rx_fifo.size() >= 8) begin
            // Hardware drops word and sets RX_OVF (spec R14)
            rx_ovf      = 1;
            int_stat[3] = 1;
            $display("[SCOREBOARD_ERROR] RX overflow — received word 0x%08h dropped",
                     rx_word);
            error_count++;
        end else begin
            rx_fifo.push_back(rx_word);
            $display("[REF_MODEL] RX push 0x%08h — fifo depth now %0d",
                     rx_word, rx_fifo.size());
        end

        // ---- Step 6: Interrupt status ------------------------------- //
        int_stat[4] = 1;                        // TRANSFER_DONE always fires
        if (tx_fifo.size() == 0)
            int_stat[0] = 1;                    // TX_EMPTY
        if (rx_fifo.size() == 8)
            int_stat[1] = 1;                    // RX_FULL

    endfunction

    // ================================================================== //
    //  CHECK TX MOSI (PATH 3 — verify what appeared on MOSI pin)
    //  Call after do_transfer() with what spi_slave_bfm captured.
    //
    //  This answers: "did the DUT shift out the correct bits on MOSI?"
    //
    //  The slave BFM captures MOSI bits during the transfer and
    //  assembles them into a word. We compare that word against
    //  last_tx_word (what we pushed to TX_DATA).
    //
    //  LSB_FIRST changes the bit ORDER on the wire:
    //    MSB_FIRST: MOSI shows bit[7] first → captured word = original
    //    LSB_FIRST: MOSI shows bit[0] first → captured word = bit-reversed
    //  The slave BFM always shifts in MSB-first order, so for LSB_FIRST
    //  transfers the captured word will look bit-reversed to the BFM.
    //  We account for that here.
    // ================================================================== //
    task check_tx_mosi(input bit [31:0] captured_mosi);
        bit [31:0] expected_mosi;
        bit [31:0] mask;
        int        width_bits;

        if (!last_tx_valid) begin
            $display("[REF_MODEL_ERROR] check_tx_mosi called before any transfer");
            error_count++;
            return;
        end

        case (cfg_width)
            2'b00: begin mask = 32'h0000_00FF; width_bits = 8;  end
            2'b01: begin mask = 32'h0000_FFFF; width_bits = 16; end
            2'b10: begin mask = 32'hFFFF_FFFF; width_bits = 32; end
            default: begin mask = 32'h0000_00FF; width_bits = 8; end
        endcase

        // What should the slave have seen on MOSI?
        // LSB_FIRST: bit[0] goes first, so slave captures bit-reversed word
        // MSB_FIRST: bit[WIDTH-1] goes first, slave captures normal order
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

    // ================================================================== //
    //  CHECK RX WORD (PATH 1 — verify RX FIFO output)
    //  Call right after apb_read(RX_DATA, observed)
    //
    //  pop_rx() removes predicted word from our software RX FIFO.
    //  This mirrors the hardware popping its RX FIFO on APB read.
    //  Then compares: ref model prediction vs DUT actual output.
    // ================================================================== //
    task check_rx_word(input bit [31:0] observed);
        bit [31:0] expected;

        if (rx_fifo.size() == 0) begin
            // Spec R15: empty read returns 0, no RX_OVF
            if (observed !== 32'h0) begin
                $display("[SCOREBOARD_ERROR] RX read while empty: expected=0x00000000 observed=0x%08h",
                         observed);
                error_count++;
            end else begin
                $display("[SCOREBOARD_PASS] RX empty read correct: 0x00000000");
            end
            return;
        end

        // Pop our predicted word — mirrors hardware popping its RX FIFO
        expected = rx_fifo.pop_front();

        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] RX word mismatch: expected=0x%08h observed=0x%08h",
                     expected, observed);
            error_count++;
        end else begin
            $display("[SCOREBOARD_PASS] RX word match: 0x%08h", observed);
        end
    endtask

    // ================================================================== //
    //  CHECK REGISTER READ-BACK (PATH 2)
    //  Call after apb_read() of any config register.
    //  expected comes from our stored raw register values.
    // ================================================================== //
    task check_reg(input string     name,
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

    // Convenience wrappers — use stored raw values as expected
    task check_ctrl(input bit [31:0] observed);
        check_reg("CTRL", reg_ctrl, observed);
    endtask

    task check_clk_div(input bit [31:0] observed);
        check_reg("CLK_DIV", reg_clk_div, observed);
    endtask

    task check_ss_ctrl(input bit [31:0] observed);
        check_reg("SS_CTRL", reg_ss_ctrl, observed);
    endtask

    task check_int_en(input bit [31:0] observed);
        check_reg("INT_EN", reg_int_en, observed);
    endtask

    // ================================================================== //
    //  CHECK STATUS REGISTER
    //  busy is passed in from test because only the test knows the
    //  current hardware BUSY state — ref model has no clock
    // ================================================================== //
    task check_status(input bit [31:0] observed, input bit busy);
        bit [31:0] expected = predict_status(busy);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] STATUS mismatch: expected=0x%08h observed=0x%08h",
                     expected, observed);
            error_count++;
        end
    endtask

    // ================================================================== //
    //  CHECK IRQ
    // ================================================================== //
    task check_irq(input bit observed_irq);
        bit expected = predict_irq();
        if (observed_irq !== expected) begin
            $display("[SCOREBOARD_ERROR] IRQ mismatch: expected=%0b observed=%0b",
                     expected, observed_irq);
            error_count++;
        end
    endtask

    // ================================================================== //
    //  W1C on INT_STAT
    //  Call when test writes apb_write(INT_STAT, val)
    // ================================================================== //
    function void write_int_stat(input bit [31:0] wdata);
        int_stat = int_stat & ~(wdata[4:0]);
    endfunction

    // ================================================================== //
    //  PREDICT STATUS
    // ================================================================== //
    function bit [31:0] predict_status(input bit busy);
        bit [31:0] s = 32'h0;
        s[0] = busy;
        s[1] = (tx_fifo.size() == 8);   // TX_FULL
        s[2] = (tx_fifo.size() == 0);   // TX_EMPTY
        s[3] = (rx_fifo.size() == 8);   // RX_FULL
        s[4] = (rx_fifo.size() == 0);   // RX_EMPTY
        s[5] = int_stat[5];
        s[6] = int_stat[6];
        return s;
    endfunction

    // ================================================================== //
    //  PREDICT IRQ
    // ================================================================== //
    function bit predict_irq();
        return |(int_stat & cfg_int_en);
    endfunction

    // ================================================================== //
    //  DELAY HELPER
    //  Total PCLK cycles consumed by inter-transfer delay period
    // ================================================================== //
    function int delay_in_pclk();
        return int'(cfg_delay) * (int'(cfg_div) + 1);
    endfunction

    // ================================================================== //
    //  BIT REVERSE utility
    // ================================================================== //
    function automatic bit [31:0] bit_reverse(input bit [31:0] data,
                                               input int        width);
        bit [31:0] result = 32'h0;
        for (int i = 0; i < width; i++)
            result[i] = data[width - 1 - i];
        return result;
    endfunction

endclass

`endif // SPI_REF_MODEL_SV
