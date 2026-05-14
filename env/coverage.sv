// =============================================================================
// coverage.sv  - Functional Coverage Collector
// -----------------------------------------------------------------------------
// SPI Master Functional Coverage
// =============================================================================

`ifndef SPI_COVERAGE_SV
`define SPI_COVERAGE_SV

class spi_coverage_col;


    // -------------------------------------------------------------------------
    // Configuration coverage
    // -------------------------------------------------------------------------
    covergroup config_cg with function sample(bit [1:0] mode, bit lsb_first, bit [1:0] width);
        option.per_instance = 1;
        option.name = "config_cg";
        
        MODE: coverpoint mode {
            bins mode0 = {2'b00};  // CPOL=0, CPHA=0
            bins mode1 = {2'b01};  // CPOL=0, CPHA=1
            bins mode2 = {2'b10};  // CPOL=1, CPHA=0
            bins mode3 = {2'b11};  // CPOL=1, CPHA=1
        }
        
        LSB: coverpoint lsb_first {
            bins msb_first = {1'b0};
            bins lsb_first = {1'b1};
        }
        
        WIDTH: coverpoint width {
            bins width8  = {2'b00};
            bins width16 = {2'b01};
            bins width32 = {2'b10};
            illegal_bins reserved = {2'b11};
        }
        
        CROSS_MODE_WIDTH: cross MODE, WIDTH;
    endgroup

    // -------------------------------------------------------------------------
    // Clock divider coverage
    // -------------------------------------------------------------------------
    covergroup clk_div_cg with function sample(bit [15:0] clk_div);
        option.per_instance = 1;
        option.name = "clk_div_cg";
        
        CLK_DIV: coverpoint clk_div {
            bins div0    = {16'h0000};  // Minimum
            bins div1    = {16'h0001};
            bins small_val   = {[16'h0002:16'h000A]};
            bins medium_val  = {[16'h000B:16'h0100]};
            bins large_val  = {[16'h0101:16'hFFFE]};
            bins div_max = {16'hFFFF};
        }
    endgroup

    // -------------------------------------------------------------------------
    // Interrupt coverage
    // -------------------------------------------------------------------------
    covergroup interrupt_cg with function sample(bit [4:0] int_sources);
        option.per_instance = 1;
        option.name = "interrupt_cg";
        
        INT_TX_EMPTY: coverpoint int_sources[0] {
            bins not_set = {1'b0};
            bins set     = {1'b1};
        }
        
        INT_RX_FULL: coverpoint int_sources[1] {
            bins not_set = {1'b0};
            bins set     = {1'b1};
        }
        
        INT_TX_OVF: coverpoint int_sources[2] {
            bins not_set = {1'b0};
            bins set     = {1'b1};
        }
        
        INT_RX_OVF: coverpoint int_sources[3] {
            bins not_set = {1'b0};
            bins set     = {1'b1};
        }
        
        INT_DONE: coverpoint int_sources[4] {
            bins not_set = {1'b0};
            bins set     = {1'b1};
        }
    endgroup

    // -------------------------------------------------------------------------
    // FIFO coverage
    // -------------------------------------------------------------------------
    covergroup fifo_cg with function sample(bit [2:0] tx_level, bit [2:0] rx_level);
        option.per_instance = 1;
        option.name = "fifo_cg";
        
        TX_LEVEL: coverpoint tx_level {
            bins empty = {3'b000};
            bins low   = {[3'b001:3'b011]};
            bins high  = {[3'b100:3'b110]};
            bins full  = {3'b111};
        }
        
        RX_LEVEL: coverpoint rx_level {
            bins empty = {3'b000};
            bins low   = {[3'b001:3'b011]};
            bins high  = {[3'b100:3'b110]};
            bins full  = {3'b111};
        }
    endgroup

    // -------------------------------------------------------------------------
    // Slave select coverage
    // -------------------------------------------------------------------------
    covergroup ss_cg with function sample(bit [3:0] ss_en, bit [3:0] ss_val);
        option.per_instance = 1;
        option.name = "ss_cg";
        
        SS_EN: coverpoint ss_en {
            bins none   = {4'h0};
            bins single = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
            bins multi  = { 
                            4'b0011, 4'b0101, 4'b0110,
                            4'b1001, 4'b1010, 4'b1100,
                            4'b0111, 4'b1011, 4'b1101, 4'b1110, 4'b1111
                };
        }
    endgroup

    // -------------------------------------------------------------------------
    // Delay parameter coverage
    // -------------------------------------------------------------------------
    covergroup delay_cg with function sample(bit [7:0] delay_val);
        option.per_instance = 1;
        option.name = "delay_cg";
        
        DELAY: coverpoint delay_val {
            bins delay_zero = {8'h00};
            bins delay_small = {[8'h01:8'h0F]};
            bins delay_mid = {[8'h10:8'h7F]};
            bins delay_large = {[8'h80:8'hFE]};
            bins delay_max = {8'hFF};
        }
    endgroup

    // -------------------------------------------------------------------------
    // Loopback mode coverage
    // -------------------------------------------------------------------------
    covergroup loopback_cg with function sample(bit loopback_en);
        option.per_instance = 1;
        option.name = "loopback_cg";
        
        LOOPBACK: coverpoint loopback_en {
            bins normal = {1'b0};
            bins loopback = {1'b1};
        }
    endgroup

    // -------------------------------------------------------------------------
    // Status flags coverage (cross with mode)
    // -------------------------------------------------------------------------
    covergroup status_cross_cg with function sample(
        bit [1:0] mode,
        bit busy, bit tx_full, bit tx_empty, 
        bit rx_full, bit rx_empty
    );
        option.per_instance = 1;
        option.name = "status_cross_cg";
        
        MODE_STA: coverpoint mode {
            bins mode0 = {2'b00};
            bins mode1 = {2'b01};
            bins mode2 = {2'b10};
            bins mode3 = {2'b11};
        }
        
        TX_STATE: coverpoint {tx_full, tx_empty} {
            bins empty    = {2'b10};
            bins full     = {2'b01};
            bins partial  = {2'b00};
            illegal_bins bad = {2'b11};
        }
        
        RX_STATE: coverpoint {rx_full, rx_empty} {
            bins empty    = {2'b10};
            bins full     = {2'b01};
            bins partial  = {2'b00};
            illegal_bins bad = {2'b11};
        }
        
        MODE_TX_CROSS: cross MODE_STA, TX_STATE;
        MODE_RX_CROSS: cross MODE_STA, RX_STATE;
    endgroup

    // -------------------------------------------------------------------------
    // Data pattern coverage
    // -------------------------------------------------------------------------
    covergroup data_pattern_cg with function sample(bit [31:0] data);
        option.per_instance = 1;
        option.name = "data_pattern_cg";
        
        DATA_PATTERN: coverpoint data {
            bins pattern_00  = {32'h00000000};
            bins pattern_ff  = {32'hFFFFFFFF};
            bins pattern_aa  = {32'hAAAAAAAA};
            bins pattern_55  = {32'h55555555};
            bins pattern_f0  = {32'hF0F0F0F0};
            bins pattern_0f  = {32'h0F0F0F0F};
            bins pattern_rand = default;
        }
    endgroup

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new();
        config_cg = new();
        clk_div_cg = new();
        interrupt_cg = new();
        fifo_cg = new();
        ss_cg = new();
        delay_cg = new();
        loopback_cg = new();
        status_cross_cg = new();
        data_pattern_cg = new();
    endfunction

    // -------------------------------------------------------------------------
    // Sample methods
    // -------------------------------------------------------------------------
    function void sample_config(bit [1:0] mode, bit lsb_first, bit [1:0] width);
        config_cg.sample(mode, lsb_first, width);
    endfunction

    function void sample_clk_div(bit [15:0] clk_div);
        clk_div_cg.sample(clk_div);
    endfunction

    function void sample_interrupt(bit [4:0] int_sources);
        interrupt_cg.sample(int_sources);
    endfunction

    function void sample_fifo(bit [2:0] tx_level, bit [2:0] rx_level);
        fifo_cg.sample(tx_level, rx_level);
    endfunction

    function void sample_ss(bit [3:0] ss_en, bit [3:0] ss_val);
        ss_cg.sample(ss_en, ss_val);
    endfunction

    function void sample_delay(bit [7:0] delay_val);
        delay_cg.sample(delay_val);
    endfunction

    function void sample_loopback(bit loopback_en);
        loopback_cg.sample(loopback_en);
    endfunction

    function void sample_status_cross(
        bit [1:0] mode,
        bit busy, bit tx_full, bit tx_empty,
        bit rx_full, bit rx_empty
    );
        status_cross_cg.sample(mode, busy, tx_full, tx_empty, rx_full, rx_empty);
    endfunction

    function void sample_data_pattern(bit [31:0] data);
        data_pattern_cg.sample(data);
    endfunction

    // -------------------------------------------------------------------------
    // Get coverage percentage
    // -------------------------------------------------------------------------
    function real get_coverage();
        real total = 0;
        int count = 0;
        total += config_cg.get_coverage();
        count++;
        total += clk_div_cg.get_coverage();
        count++;
        total += interrupt_cg.get_coverage();
        count++;
        total += fifo_cg.get_coverage();
        count++;
        total += ss_cg.get_coverage();
        count++;
        total += delay_cg.get_coverage();
        count++;
        total += loopback_cg.get_coverage();
        count++;
        total += status_cross_cg.get_coverage();
        count++;
        total += data_pattern_cg.get_coverage();
        count++;
        return total / real'(count);
    endfunction

endclass

`endif // SPI_COVERAGE_SV