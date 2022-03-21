// Copyright (c) 2021-2022 Spencer Chang

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

`resetall
`timescale 1ns / 1ps
`default_nettype none

module spi_master #
(
    parameter AXIS_DATA_WIDTH = 8,
    parameter PRESCALE_WIDTH = 8
)
(
    input  wire                         clk,
    input  wire                         rst,

    /*
     * AXIS Input
     */
    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,

    /*
     * AXIS Output
     */
    output wire [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,

    /*
     * SPI
     */
    output wire                         sclk,
    output wire                         mosi,
    input  wire                         miso,

    /*
     * Configuration
     */
    input  wire [1:0]                       spi_mode,
    input  wire [PRESCALE_WIDTH-1:0]        sclk_prescale,
    input  wire [WORD_COUNTER_WIDTH-1:0]    spi_word_width,

    /*
     * Status
     */
    output wire                         rx_overrun_error,
    output wire                         bus_active
);

localparam WORD_COUNTER_WIDTH = $clog2(AXIS_DATA_WIDTH) + 1;

enum reg [1:0] {IDLE, TRANSFER} master_state = IDLE;

// axis
reg [AXIS_DATA_WIDTH-1:0] m_axis_tdata_reg = 0;
reg m_axis_tvalid_reg = 0;
assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;
assign s_axis_tready = (master_state == IDLE);

// mosi
reg mosi_reg = 0;
reg miso_reg = 0;
assign mosi = mosi_reg;

// status
reg rx_overrun_error_reg = 0;
reg active = 0;
assign bus_active = (master_state != IDLE);
reg seen_posedge_sclk;

// spi mode
reg [1:0] spi_mode_buff;
wire cpol, cpha;
assign cpol = (spi_mode_buff === 2) | (spi_mode_buff === 3);
assign cpha = (spi_mode_buff === 1) | (spi_mode_buff === 3);

// spi word length
reg [WORD_COUNTER_WIDTH-1:0] spi_word_width_buff = AXIS_DATA_WIDTH;
reg [WORD_COUNTER_WIDTH-1:0] bit_out_cnt = 0;
reg [WORD_COUNTER_WIDTH-1:0] bit_in_cnt = 0;

// spi transaction contents
reg [AXIS_DATA_WIDTH-1:0] data_o_reg = 0;
reg [AXIS_DATA_WIDTH-1:0] data_i_reg = 0;

always_ff @(posedge clk) begin : proc_spi_transaction
    if (rst) begin
        master_state <= IDLE;
        mosi_reg <= 0;
        data_i_reg <= 0;
        rx_overrun_error_reg <= 0;
        seen_posedge_sclk <= 0;
    end else begin
        miso_reg <= miso;

        // handle an axis transaction
        if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid_reg <= 0;
            rx_overrun_error_reg <= 0;
        end

        // state machine
        case (master_state)
            IDLE: begin
                if (s_axis_tvalid && s_axis_tready) begin
                    // configurable inputs
                    spi_mode_buff <= spi_mode;
                    spi_word_width_buff <= spi_word_width;
                    sclk_prescale_buff <= sclk_prescale;

                    data_o_reg <= s_axis_tdata;
                    data_i_reg <= 0;

                    seen_posedge_sclk <= 0;
                    bit_in_cnt <= 0;
                    bit_out_cnt <= 0;
                    master_state <= TRANSFER;
                end
            end
            TRANSFER: begin
                // according to https://www.analog.com/en/analog-dialogue/articles/introduction-to-spi-interface.html
                // the timing diagrams say that we will treat the rising edge as our first edge

                // for cpha = 0, the rising edge is sampling, so we must prepare data on the wire
                // before we see any clocks (as soon as we transition to the transfer state)
                if ((~cpha) && (bit_out_cnt==0)) begin
                    mosi_reg <= data_o_reg[spi_word_width_buff - 1];
                    data_o_reg <= data_o_reg << 1;
                    bit_out_cnt <= bit_out_cnt + 1;
                end

                if (sclk_rising_edge) begin
                    seen_posedge_sclk <= 1;
                end

                // read stage
                if (sclk_read_edge && (seen_posedge_sclk | sclk_rising_edge)) begin
                    data_i_reg <= {data_i_reg[AXIS_DATA_WIDTH-2:0], miso_reg};
                    bit_in_cnt <= bit_in_cnt + 1;
                end

                // write stage
                if (sclk_write_edge && (seen_posedge_sclk | sclk_rising_edge)) begin
                    mosi_reg <= data_o_reg[spi_word_width_buff - 1];
                    data_o_reg <= data_o_reg << 1;
                    bit_out_cnt <= bit_out_cnt + 1;
                end

                // the last step of spi transaction in any mode is a read
                // so we will check for done by doing a spi read
                if (bit_in_cnt == spi_word_width_buff) begin
                    master_state <= IDLE;

                    // write data back to axis
                    m_axis_tvalid_reg <= 1;
                    m_axis_tdata_reg <= data_i_reg;

                    rx_overrun_error_reg <= m_axis_tvalid_reg;
                end

            end
            default: master_state <= IDLE;
        endcase
    end
end



// generate sclk signal
wire sclk_en;
assign sclk_en = (master_state != IDLE);

reg [PRESCALE_WIDTH-1:0] sclk_prescale_buff;
reg [PRESCALE_WIDTH-1:0] prescale_counter;

reg sclk_buff = 0;
assign sclk = sclk_buff;

// keep track of edges
reg sclk_last;
wire sclk_read_edge;
wire sclk_write_edge;
wire sclk_rising_edge;
assign sclk_read_edge = (cpha) ? (sclk_last & ~sclk) : (~sclk_last & sclk);
assign sclk_write_edge = (cpha) ? (~sclk_last & sclk) : (sclk_last & ~sclk);
assign sclk_rising_edge = (~sclk_last & sclk);

always_ff @(posedge clk) begin : proc_sclk_gen
    if (rst) begin
        prescale_counter <= 0;
        sclk_last <= 0;
    end else begin
        if (sclk_en) begin
            prescale_counter <= prescale_counter + 1;
            if (prescale_counter == sclk_prescale_buff >> 1) begin
                sclk_buff <= !sclk_buff;
                prescale_counter <= 0;
            end
        end else begin
            // let the sclk idle according to the polarity
            sclk_buff <= cpol;
            prescale_counter <= 0;
        end
        sclk_last <= sclk;
    end
end


endmodule : spi_master

`resetall