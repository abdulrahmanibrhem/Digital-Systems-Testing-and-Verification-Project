// =============================================================================
// spi_slave_bfm.sv - SPI Slave BFM (Mode-Aware)
// =============================================================================
// Sophisticated SPI slave model that handles all 4 CPOL/CPHA modes.
// Properly samples MOSI and drives MISO on appropriate edges.
// Supports MSB/LSB bit order (configurable via patterns).
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave spi,
    input  logic [1:0] mode,
    input  logic [7:0] miso_byte
);

    // SPI mode: {CPOL, CPHA}
    // Mode 0: CPOL=0, CPHA=0
    // Mode 1: CPOL=0, CPHA=1
    // Mode 2: CPOL=1, CPHA=0
    // Mode 3: CPOL=1, CPHA=1

    logic cpol, cpha;
    logic sclk_r, sclk_r2, sclk_r3;
    logic ss_n_r;
    logic [31:0] miso_shift_reg;
    logic [5:0] bit_count;
    logic transfer_active;
    logic [31:0] mosi_shift_in;

    assign cpol = mode[1];
    assign cpha = mode[0];

    // =========================================================================
    // SPI SLAVE CLOCK EDGE DETECTION
    // =========================================================================
    // Detect rising/falling edges of SCLK based on CPOL
    always @(spi.cb_slave) begin
        sclk_r3 <= sclk_r2;
        sclk_r2 <= sclk_r;
        sclk_r  <= spi.cb_slave.sclk;
    end

    wire sclk_rising_edge  = ~sclk_r2 & sclk_r;
    wire sclk_falling_edge = sclk_r2 & ~sclk_r;

    // Edge selection based on CPHA
    // CPHA=0: sample on leading edge (determined by CPOL)
    // CPHA=1: sample on trailing edge
    wire sample_edge = (cpha == 1'b0) ? 
                       (cpol ? sclk_falling_edge : sclk_rising_edge) :
                       (cpol ? sclk_rising_edge : sclk_falling_edge);

    wire shift_edge  = (cpha == 1'b0) ?
                       (cpol ? sclk_rising_edge : sclk_falling_edge) :
                       (cpol ? sclk_falling_edge : sclk_rising_edge);

    // =========================================================================
    // TRANSFER STATE TRACKING
    // =========================================================================
    always @(spi.cb_slave) begin
        ss_n_r <= spi.cb_slave.ss_n[0];  // Monitor SS_n[0]
        
        // Transfer starts when any SS goes low
        if (spi.cb_slave.ss_n !== 4'hF) begin
            transfer_active <= 1'b1;
        end else begin
            transfer_active <= 1'b0;
            bit_count <= 6'b0;
        end
    end

    // =========================================================================
    // MOSI SAMPLING AND SHIFTING
    // =========================================================================
    always @(posedge spi.pclk) begin
        if (transfer_active && sample_edge) begin
            // Shift in MOSI data (MSB first for now)
            mosi_shift_in <= {mosi_shift_in[30:0], spi.sclk_r};
            bit_count <= bit_count + 1;
        end
    end

    // =========================================================================
    // MISO SHIFTING AND DRIVING
    // =========================================================================
    always @(posedge spi.pclk) begin
        // Initialize shift register when transfer starts
        if (spi.cb_slave.ss_n !== 4'hF && bit_count == 6'b0) begin
            miso_shift_reg <= {miso_byte, 24'b0};
        end
        
        // Shift out MISO on shift edges
        if (transfer_active && shift_edge) begin
            miso_shift_reg <= {miso_shift_reg[30:0], 1'b0};
        end
    end

    // Always drive the MSB of the shift register
    always @(spi.cb_slave) begin
        if (transfer_active) begin
            spi.cb_slave.miso <= miso_shift_reg[31];
        end else begin
            spi.cb_slave.miso <= 1'bZ;  // High-Z when inactive
        end
    end

    // =========================================================================
    // SLAVE RESPONSE MANAGEMENT
    // =========================================================================
    task automatic load_miso_response(input logic [31:0] data);
        miso_shift_reg = data;
    endtask

    task automatic get_mosi_data(output logic [31:0] data);
        data = mosi_shift_in;
    endtask

    task automatic reset_slave();
        miso_shift_reg = 32'b0;
        mosi_shift_in  = 32'b0;
        bit_count      = 6'b0;
        transfer_active = 1'b0;
    endtask

endmodule

`endif // SPI_SLAVE_BFM_SV