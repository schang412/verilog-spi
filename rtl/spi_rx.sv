`timescale 1ns / 1ps


module spi_rx #
(
    parameter AXIS_DATA_WIDTH = 8 // MAX=64
)
(
    input  wire clk,
    input  wire rst,

    /*
     * AXIS output
     */
    output wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,

    /*
     * SPI Interface
     */
    input  wire                     sclk,
    input  wire                     rxd,

    /*
     * Configuration
     */
    input  wire [1:0]               spi_mode,
    input  wire [5:0]               spi_word_width,

    /*
     * Status
     */
    output wire                     busy,
    output wire                     overrun_error
);

wire cpha;
assign cpha = (spi_mode == 1) | (spi_mode == 2);

reg sclk_last_reg = 0;
reg rxd_reg = 1;

reg [AXIS_DATA_WIDTH-1:0] data_reg = 0;
reg [5:0] bit_cnt = 0;

reg [AXIS_DATA_WIDTH-1:0] m_axis_tdata_reg = 0;
reg m_axis_tvalid_reg = 0;
assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;

reg [5:0] spi_word_width_reg = AXIS_DATA_WIDTH;

reg busy_reg = 0;
reg overrun_error_reg = 0;
assign busy = busy_reg;
assign overrun_error = overrun_error_reg;

always_ff @(posedge clk) begin
    if(rst) begin
        m_axis_tvalid_reg <= 0;
        sclk_last_reg <= sclk;
        rxd_reg <= 1;
        busy_reg <= 0;
        overrun_error_reg <= 0;
        data_reg <= 0;
        bit_cnt <= 0;

    end else begin
        sclk_last_reg <= sclk;
        rxd_reg <= rxd;

        if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid_reg <= 0;
            bit_cnt <= 0;
            overrun_error_reg <= 0;
        end

        // sclk sampling edge
        if ((sclk_last_reg == cpha) && (sclk == !cpha)) begin
            busy_reg <= 1;

            data_reg <= {data_reg[AXIS_DATA_WIDTH-2:0], rxd_reg};
            bit_cnt <= bit_cnt + 1;

        end else begin
            if (bit_cnt == 0) begin
                data_reg <= 0;
                busy_reg <= 0;
            end
        end

        if (bit_cnt == spi_word_width_reg) begin
            bit_cnt <= 0;
            m_axis_tvalid_reg <= 1;
            m_axis_tdata_reg <= data_reg;
            overrun_error_reg <= m_axis_tvalid_reg;
        end
        if (!busy_reg) begin
            spi_word_width_reg <= spi_word_width;
        end
    end
end

endmodule : spi_rx