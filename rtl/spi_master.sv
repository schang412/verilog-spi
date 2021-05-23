`timescale 1ns / 1ps

module spi_master #
(
    parameter DATA_WIDTH = 8, // max = 64
    parameter SCLK_PRESCALE = 4,
    parameter SPI_MODE = 0 // mode = {0, 1, 2, 3}
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * AXIS Input
     */

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,

    /*
     * AXIS Output
     */

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,

    /*
     * SPI
     */

    output wire                  sclk,
    output wire                  mosi,
    input  wire                  miso,

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
    .DATA_WIDTH(DATA_WIDTH),
    .SPI_MODE(SPI_MODE)
) spi_rx_inst (
    .clk(clk),
    .rst(rst),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),

    .sclk          (sclk_int),
    .rxd           (miso),

    .busy          (rx_busy),
    .overrun_error (rx_overrun_error)
);

spi_tx #(
    .DATA_WIDTH(DATA_WIDTH),
    .SCLK_PRESCALE(SCLK_PRESCALE),
    .SPI_MODE(SPI_MODE)
) spi_tx_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),

    .sclk          (sclk_int),
    .txd           (mosi),

    .busy          (tx_busy)
);

endmodule : spi_master
