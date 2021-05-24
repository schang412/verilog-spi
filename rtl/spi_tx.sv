`timescale 1ns / 1ps


module spi_tx #
(
    parameter AXIS_DATA_WIDTH = 8 // MAX=64
)
(
    input  wire clk,
    input  wire rst,

    // AXIS Input (MSB out first)
    input  wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,

    // Interface
    output wire                     sclk,
    output wire                     txd,

    // Configuration
    input  wire [1:0]               spi_mode,
    input  wire [7:0]               sclk_prescale,
    input  wire [5:0]               spi_word_width, // sampled on an AXIS transaction

    // Status
    output wire                     busy
);


reg busy_reg = 0;
assign s_axis_tready = !busy_reg;
assign busy = busy_reg;

reg [7:0] prescale_counter_reg = 0;

reg [5:0] spi_word_width_reg = AXIS_DATA_WIDTH;
reg [AXIS_DATA_WIDTH-1:0] data_reg = 0;
reg [5:0] bit_cnt = 0;

wire cpol;
wire cpha;
assign cpol = (spi_mode == 2) | (spi_mode == 3);
assign cpha = (spi_mode == 1) | (spi_mode == 2);

reg sclk_reg = cpol;
assign sclk = sclk_reg;

reg txd_reg = 0;
assign txd = txd_reg;

enum reg [1:0] {IDLE, SHIFT_BIT, PUT_ON_WIRE, FINAL_BIT} tx_state = IDLE;

always_ff @(posedge clk) begin
    if (rst) begin
        txd_reg <= 0;
        busy_reg <= 0;
        data_reg <= 0;
        bit_cnt <= 0;
        tx_state <= IDLE;
        sclk_reg <= cpol;
    end else begin

        if (s_axis_tvalid==1 && s_axis_tready==1) begin
            spi_word_width_reg <= spi_word_width;
            data_reg <= s_axis_tdata;
            busy_reg <= 1;
        end

        prescale_counter_reg <= prescale_counter_reg + 1;
        if (prescale_counter_reg == (sclk_prescale >> 1)) begin
            prescale_counter_reg <= 1;
            case (tx_state)
                IDLE: begin
                    txd_reg <= 0;
                    sclk_reg <= cpol;
                    if (busy_reg == 1) begin
                        if (cpol != cpha) sclk_reg <= cpha;
                        txd_reg <= data_reg[spi_word_width-1];
                        bit_cnt <= 1;
                        tx_state <= SHIFT_BIT;
                    end
                end
                SHIFT_BIT: begin
                    data_reg <= data_reg << 1;
                    sclk_reg <= !cpha;
                    if (bit_cnt == spi_word_width_reg) begin
                        tx_state <= FINAL_BIT;
                    end else begin
                        tx_state <= PUT_ON_WIRE;
                    end
                end
                PUT_ON_WIRE: begin
                    tx_state <= SHIFT_BIT;
                    sclk_reg <= cpha;
                    txd_reg <= data_reg[spi_word_width-1];
                    bit_cnt <= bit_cnt + 1;
                end
                FINAL_BIT: begin
                    if (cpol == cpha) sclk_reg <= cpha;
                    if (busy_reg == 1) begin
                        tx_state <= IDLE;
                        txd_reg <= data_reg[spi_word_width-1];
                        busy_reg <= 0;
                    end else tx_state <= IDLE;
                end
                default: tx_state <= IDLE;
            endcase
        end
    end
end

endmodule : spi_tx