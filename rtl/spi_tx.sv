`timescale 1ns / 1ps


module spi_tx #
(
    parameter DATA_WIDTH = 8, // MAX=64
    parameter SCLK_PRESCALE = 4,
    parameter SPI_MODE = 0
)
(
    input  wire clk,
    input  wire rst,

    // AXIS Input (MSB out first)
    input  wire [DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,

    // Interface
    // txd is valid on sclk rising edge
    output wire                     sclk,
    output wire                     txd,

    // Status
    output wire                     busy
);

localparam CPOL = (SPI_MODE == 2) | (SPI_MODE == 3);
localparam CPHA = (SPI_MODE == 1) | (SPI_MODE == 2);

reg txd_reg = 0;
reg busy_reg = 0;

reg [SCLK_PRESCALE-1:0] prescale_counter_reg = 0;

reg [DATA_WIDTH-1:0] data_reg = 0;
reg [5:0] bit_cnt = 0;

reg sclk_reg = CPOL;


assign s_axis_tready = !busy_reg;
assign txd = txd_reg;

assign busy = busy_reg;

enum reg [1:0] {IDLE, SHIFT_BIT, PUT_ON_WIRE, FINAL_BIT} tx_state = IDLE;

assign sclk = sclk_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        txd_reg <= 0;
        busy_reg <= 0;
        data_reg <= 0;
        bit_cnt <= 0;
        tx_state <= IDLE;
        sclk_reg <= CPOL;
    end else begin

        if (s_axis_tvalid==1 && s_axis_tready==1) begin
            data_reg <= s_axis_tdata;
            busy_reg <= 1;
        end

        prescale_counter_reg <= prescale_counter_reg + 1;
        if (prescale_counter_reg == 0) begin
            case (tx_state)
                IDLE: begin
                    txd_reg <= 0;
                    sclk_reg <= CPOL;
                    if (busy_reg == 1) begin
                        if (CPOL != CPHA) sclk_reg <= CPHA;
                        txd_reg <= data_reg[DATA_WIDTH-1];
                        bit_cnt <= 1;
                        tx_state <= SHIFT_BIT;
                    end
                end
                SHIFT_BIT: begin
                    data_reg <= data_reg << 1;
                    sclk_reg <= !CPHA;
                    if (bit_cnt == DATA_WIDTH) begin
                        tx_state <= FINAL_BIT;
                    end else begin
                        tx_state <= PUT_ON_WIRE;
                    end
                end
                PUT_ON_WIRE: begin
                    tx_state <= SHIFT_BIT;
                    sclk_reg <= CPHA;
                    txd_reg <= data_reg[DATA_WIDTH-1];
                    bit_cnt <= bit_cnt + 1;
                end
                FINAL_BIT: begin
                    if (CPOL == CPHA) sclk_reg <= CPHA;
                    if (busy_reg == 1) begin
                        tx_state <= IDLE;
                        txd_reg <= data_reg[DATA_WIDTH-1];
                        busy_reg <= 0;
                    end else tx_state <= IDLE;
                end
                default: tx_state <= IDLE;
            endcase
        end
    end
end


endmodule : spi_tx