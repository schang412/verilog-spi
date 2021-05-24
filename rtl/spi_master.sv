`timescale 1ns / 1ps

module spi_master #
(
    parameter AXIS_DATA_WIDTH = 8 // max = 64
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * AXIS Input
     */
    input  wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,

    /*
     * AXIS Output
     */
    output wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,

    /*
     * SPI
     */
    output wire                  sclk,
    output wire                  mosi,
    input  wire                  miso,

    /*
     * Configuration
     */
    input  wire [1:0]            spi_mode,
    input  wire [7:0]            sclk_prescale,
    input  wire [5:0]            spi_word_width,

    /*
     * Status
     */
    output wire                  tx_busy,
    output wire                  rx_busy,
    output wire                  rx_overrun_error
);

wire sclk_int;
assign sclk = sclk_int;

spi_rx #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
) spi_rx_inst (
    .clk(clk),
    .rst(rst),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),

    .spi_mode      (spi_mode),
    .spi_word_width(spi_word_width),

    .sclk          (sclk_int),
    .rxd           (miso),

    .busy          (rx_busy),
    .overrun_error (rx_overrun_error)
);

spi_tx #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
) spi_tx_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),

    .spi_mode      (spi_mode),
    .sclk_prescale (sclk_prescale),
    .spi_word_width(spi_word_width),

    .sclk          (sclk_int),
    .txd           (mosi),

    .busy          (tx_busy)
);

endmodule : spi_master
