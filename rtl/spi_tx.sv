`timescale 1ns / 1ps


module spi_tx #
(
    parameter AXIS_DATA_WIDTH = 8 // MAX=64
)
(
    input  wire sclk,
    input  wire clk,
    input  wire rst,

    // AXIS Input (MSB out first)
    input  wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,

    // Interface
    output wire                     txd,
    input logic                     tx_enable,

    // Configuration
    input  wire [1:0]               spi_mode,
    input  wire [5:0]               spi_word_width, // sampled on an AXIS transaction

    // Status
    output wire                     busy
);


reg busy_reg = 0;
assign s_axis_tready = !busy_reg;
assign busy = busy_reg;

reg [5:0] spi_word_width_reg = AXIS_DATA_WIDTH;
reg [AXIS_DATA_WIDTH-1:0] data_reg = 0;
reg [5:0] bit_cnt = 0;

wire cpol;
wire cpha;
logic phased_sclk;

assign cpol = (spi_mode === 2) | (spi_mode === 3);
assign cpha = (spi_mode === 1) | (spi_mode === 2);
assign phased_sclk = sclk ^ !cpha;

reg txd_reg = 0;
assign txd = txd_reg;

enum reg [1:0] {IDLE, SHIFT_BIT} tx_state = IDLE;

always_ff @(posedge phased_sclk) begin //Phased clk incorporates cpha, which means even if it says posedge, if cpha == 1, it would enter this always_ff at negedge cpha
    if (tx_enable) begin
        case (tx_state)
            IDLE: begin
                if (busy_reg) begin
                    busy_reg <= 1;
                    tx_state <= SHIFT_BIT;
                    //Transmitting the first bit in IDLE to have enough clock edges
                    txd_reg <= data_reg[spi_word_width_reg - 1];
                    data_reg <= data_reg << 1;
                    bit_cnt <= bit_cnt + 1;
                end
            end
            SHIFT_BIT: begin
                //Shift all bits at posedge phased_sclk
                txd_reg <= data_reg[spi_word_width_reg - 1];
                data_reg <= data_reg << 1;
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == spi_word_width_reg - 1) begin
                    tx_state <= IDLE;
                    busy_reg <= 0;
                    bit_cnt <= 0;
                end
            end
            default: tx_state <= IDLE;
        endcase
    end    
end
always_ff @(posedge clk) begin
    if (rst) begin
        txd_reg <= 0;
        busy_reg <= 0;
        data_reg <= 0;
        bit_cnt <= 0;
        tx_state <= IDLE;
    end
    if (s_axis_tvalid && s_axis_tready) begin // If enable
        spi_word_width_reg <= spi_word_width;
        data_reg <= s_axis_tdata;
        busy_reg <= 1; // s_axis_tready <= 0;
    end
end

endmodule : spi_tx