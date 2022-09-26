// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2022 Spencer Chang

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * SPI master AXI lite wrapper
 */
module spi_master_axil #
(
    parameter NUM_SS_BITS = 1, // 1-32 allowed
    parameter FIFO_EXIST = 1, // set to 0 to disable FIFO
    parameter FIFO_DEPTH = 16, // set to a power of 2

    parameter AXIL_ADDR_WIDTH = 16,
    parameter AXIL_ADDR_BASE = 0,
    parameter RB_NEXT_PTR = 0
)
(
    input  wire                         clk,
    input  wire                         rst,

    output wire                         irq,

    /*
     * Host interface
     */
    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  wire [2:0]                   s_axil_awprot,
    input  wire                         s_axil_awvalid,
    output wire                         s_axil_awready,
    input  wire [31:0]                  s_axil_wdata,
    input  wire [3:0]                   s_axil_wstrb,
    input  wire                         s_axil_wvalid,
    output wire                         s_axil_wready,
    output wire [1:0]                   s_axil_bresp,
    output wire                         s_axil_bvalid,
    input  wire                         s_axil_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axil_araddr,
    input  wire [2:0]                   s_axil_arprot,
    input  wire                         s_axil_arvalid,
    output wire                         s_axil_arready,
    output wire [31:0]                  s_axil_rdata,
    output wire [1:0]                   s_axil_rresp,
    output wire                         s_axil_rvalid,
    input  wire                         s_axil_rready,

    /*
     * SPI interface
     */
    output wire                         spi_sclk_o,
    output wire                         spi_sclk_t,
    output wire                         spi_mosi_o,
    output wire                         spi_mosi_t,
    input  wire                         spi_miso,
    output wire [NUM_SS_BITS-1:0]       spi_ncs_o,
    output wire                         spi_ncs_t
);
/*

ID Register: (AXIL_ADDR_BASE + 0x00) (RO)

Identifies that this register section contains an SPI block: 0x294E_C100


-----------------------------------------------------------------------
Revision Register: (AXIL_ADDR_BASE + 0x04) (RO)

Identifies the revision of the HDL code: 0x0000_0110


-----------------------------------------------------------------------
Pointer Register: (AXIL_ADDR_BASE + 0x08) (RO)

Contains the data specified by the parameter RB_NEXT_PTR. The intended
use is for the main driver to automatically load the respective sub-drivers
using the ID and the pointer to the next driver to be loaded.

Default: 0 (settable by parameter RB_NEXT_PTR)

-----------------------------------------------------------------------
Software Reset Register: (AXIL_ADDR_BASE + 0x10) (WO)

Write 0x0000_000A to perform a software reset


-----------------------------------------------------------------------
SPI Control Register: (AXIL_ADDR_BASE + 0x20) (RW)

*Note that changing the control register will reset the FIFO

Bit 31-16: SPI clock prescale (default 4)
Bit  15-8: SPI word width (default 8, max=32)
Bit     7: Reserved
Bit     6: Reset the FIFO
Bit     5: Manual Slave Select Assertion (default 1; 0=slave select asserted by core logic)
Bit     4: LSB First (default 0; 0=MSB first, 1=LSB first)
Bit     3: CPOL (default 0; 0=SCLK idle low, 1=SCLK Idle High)
Bit     2: CPHA (default 0; Setting this bit selects one of two fundamentally different transfer formats)
Bit     1: SPE (default 0; 0=disable, 1=SPI System Enabled)
Bit     0: LOOP (default 0; 0=Normal, 1=Loopback)


-----------------------------------------------------------------------
SPI Status Register: (AXIL_ADDR_BASE + 0x28) (RO)

Bit  31-4: Reserved
Bit     3: TX_FULL
Bit     2: TX_EMPTY
Bit     1: RX_FULL
Bit     0: RX_EMPTY


-----------------------------------------------------------------------
SPI Slave Select Register: (AXIL_ADDR_BASE + 0x2C) (RW)

Active-Low, One-hot encoded slave select vector of length N (determined by NUM_SS_BITS).
At most, one bit be asserted low and denotes which slave the master will communicate.
When more than one bit is low, only the highest bit slave select is asserted low.

Bit  31-N: Reserved
Bit N-1:0: Selected Slave


-----------------------------------------------------------------------
SPI Data Transmit Register: (AXIL_ADDR_BASE + 0x30) (WO)

The data to be transmitted aligned to the right with the MSB first. This does not depend
on LSB first transfer selection.

-----------------------------------------------------------------------
SPI Data Receive Register: (AXIL_ADDR_BASE + 0x34) (RO)

The data to received, aligned to the right with the MSB first. This does not depend
on LSB first transfer selection.

-----------------------------------------------------------------------
SPI Interrupt Status Register: (AXIL_ADDR_BASE + 0x40) (RW1C)

Write 1 to clear this register. Read this register after an IRQ pulse to determine
which enabled interrupt event was triggered.

Bit  31-4: Reserved
Bit     3: RX_OVERRUN
Bit     2: RX_FULL
Bit     1: RX_NOT_EMPTY
Bit     0: TX_EMPTY

-----------------------------------------------------------------------
SPI Interrupt Enable Register: (AXIL_ADDR_BASE + 0x44) (RW)

Set bit to 1 to control enable the interrupt event to trigger an IRQ pulse.

Default: 0

Bit  31-4: Reserved
Bit     3: RX_OVERRUN
Bit     2: RX_FULL
Bit     1: RX_NOT_EMPTY
Bit     0: TX_EMPTY

*/

// AXIL
reg s_axil_awready_reg = 1'b0, s_axil_awready_next;
reg s_axil_wready_reg = 1'b0, s_axil_wready_next;
reg s_axil_bvalid_reg = 1'b0, s_axil_bvalid_next;
reg s_axil_arready_reg = 1'b0, s_axil_arready_next;
reg [31:0] s_axil_rdata_reg = 32'd0, s_axil_rdata_next;
reg s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;
reg do_axil_write, do_axil_read;

assign s_axil_awready = s_axil_awready_reg;
assign s_axil_wready = s_axil_wready_reg;
assign s_axil_bresp = 2'b00;
assign s_axil_bvalid = s_axil_bvalid_reg;

assign s_axil_arready = s_axil_arready_reg;
assign s_axil_rdata = s_axil_rdata_reg;
assign s_axil_rresp = 2'b00;
assign s_axil_rvalid = s_axil_rvalid_reg;

// AXIS - For Transmitting
reg [31:0] axis_write_tdata = 32'd0;
reg axis_write_tvalid = 1'b0, axis_write_tvalid_next;
wire axis_write_tready;

wire [31:0] axis_write_ext_tdata;
wire axis_write_ext_tvalid;
wire axis_write_ext_tready;

// AXIS - For Receiving
wire [31:0] axis_read_tdata;
wire axis_read_tvalid;
reg  axis_read_tready = 1'b0;

wire [31:0] axis_read_ext_tdata;
wire axis_read_ext_tvalid;
wire axis_read_ext_tready;

// software reset
reg software_rst = 0;
reg fifo_rst = 0;

// SPI Control Register Low
reg mssa_reg = 1'b1;
reg lsb_first_reg = 1'b0;
reg cpol_reg = 1'b0;
reg cpha_reg = 1'b0;
reg spe_reg = 1'b0;
reg loop_reg = 1'b0;

// SPI Control Register High
reg [15:0] spi_clock_prescale_reg = 16'd4;
reg [7:0] spi_word_width_reg = 7'd8;

reg [31:0] slave_select_reg = {32{1'b1}};

// SPI Interrupt Enable Register
reg irq_en_rx_overrun = 0;
reg irq_en_rx_full = 0;
reg irq_en_rx_not_empty = 0;
reg irq_en_tx_empty = 0;

// SPI Interrupt Status Register
wire [3:0] irq_status_summary;
reg  [3:0] irq_status_summary_last = 0;
reg irq_status_rx_overrun = 0;
reg irq_status_rx_full = 0;
reg irq_status_rx_not_empty = 0;
reg irq_status_tx_empty = 0;

wire rx_overrun_error;

assign irq_status_summary = {irq_status_rx_overrun, irq_status_rx_full, irq_status_rx_not_empty, irq_status_tx_empty};
assign irq = (|(irq_status_summary & ~irq_status_summary_last) & spe_reg);

generate
    if (FIFO_EXIST) begin
        axis_fifo #(
            .DEPTH(FIFO_DEPTH),
            .DATA_WIDTH(32),
            .KEEP_ENABLE(0),
            .LAST_ENABLE(0),
            .ID_ENABLE(0),
            .DEST_ENABLE(0),
            .USER_ENABLE(0),
            .FRAME_FIFO(0)
        ) write_fifo_inst (
            .clk(clk),
            .rst(rst | software_rst | fifo_rst),
            // AXI input
            .s_axis_tdata(axis_write_tdata),
            .s_axis_tkeep(4'b0),
            .s_axis_tvalid(axis_write_tvalid),
            .s_axis_tready(axis_write_tready),
            .s_axis_tlast(1'b0),
            .s_axis_tid(8'b0),
            .s_axis_tdest(8'b0),
            .s_axis_tuser(1'b0),
            // AXI output
            .m_axis_tdata(axis_write_ext_tdata),
            .m_axis_tvalid(axis_write_ext_tvalid),
            .m_axis_tready(axis_write_ext_tready)
        );

        axis_fifo #(
            .DEPTH(FIFO_DEPTH),
            .DATA_WIDTH(32),
            .KEEP_ENABLE(0),
            .LAST_ENABLE(0),
            .ID_ENABLE(0),
            .DEST_ENABLE(0),
            .USER_ENABLE(0),
            .FRAME_FIFO(0)
        ) read_fifo_inst (
            .clk(clk),
            .rst(rst | software_rst | fifo_rst),
            // AXI input
            .s_axis_tdata(axis_read_ext_tdata),
            .s_axis_tkeep(4'b0),
            .s_axis_tvalid(axis_read_ext_tvalid),
            .s_axis_tready(axis_read_ext_tready),
            .s_axis_tlast(1'b0),
            .s_axis_tid(8'b0),
            .s_axis_tdest(8'b0),
            .s_axis_tuser(1'b0),
            // AXI output
            .m_axis_tdata(axis_read_tdata),
            .m_axis_tvalid(axis_read_tvalid),
            .m_axis_tready(axis_read_tready)
        );

    end else begin
        assign axis_write_ext_tdata = axis_write_tdata;
        assign axis_write_ext_tvalid = axis_write_tvalid;
        assign axis_write_tready = axis_write_ext_tready;

        assign axis_read_tdata = axis_read_ext_tdata;
        assign axis_read_tvalid = axis_read_ext_tvalid;
        assign axis_read_ext_tready = axis_read_tready;
    end
endgenerate

/*
 * AXIL Write Transaction
 */

always @* begin

    axis_write_tvalid_next = axis_write_tready ? 1'b0 : axis_write_tvalid;

    // axil write transaction
    do_axil_write = 1'b0;

    s_axil_awready_next = 1'b0;
    s_axil_wready_next = 1'b0;
    s_axil_bvalid_next = s_axil_bvalid_reg && !s_axil_bready;

    if (s_axil_awvalid && s_axil_wvalid && (!s_axil_bvalid || s_axil_bready) && (!s_axil_awready && !s_axil_wready)) begin
        s_axil_awready_next = 1'b1;
        s_axil_wready_next = 1'b1;
        s_axil_bvalid_next = 1'b1;

        do_axil_write = 1'b1;
    end
end
always @(posedge clk) begin
    if (rst || software_rst) begin
        s_axil_awready_reg <= 1'b0;
        s_axil_wready_reg <= 1'b0;
        s_axil_bvalid_reg <= 1'b0;
        software_rst <= 1'b0;
        axis_write_tvalid <= 1'b0;

        // restore defaults
        slave_select_reg <= {32{1'b1}};
        mssa_reg <= 1'b1;
        lsb_first_reg <= 1'b0;
        cpol_reg <= 1'b0;
        cpha_reg <= 1'b0;
        spe_reg <= 1'b0;
        loop_reg <= 1'b0;
        spi_word_width_reg <= 8'd8;
        spi_clock_prescale_reg <= 16'd4;

        irq_status_rx_overrun <= 0;
        irq_status_rx_full <= 0;
        irq_status_rx_not_empty <= 0;
        irq_status_tx_empty <= 0;

    end else begin
        // check for interrupt events
        irq_status_summary_last <= irq_status_summary;
        irq_status_rx_overrun <= irq_en_rx_overrun ? rx_overrun_error : 0;
        irq_status_rx_not_empty <= irq_en_rx_not_empty ? axis_read_tvalid : 0;
        if (FIFO_EXIST) begin
            irq_status_tx_empty <= irq_en_tx_empty ? ~axis_write_tready : 0;
            irq_status_rx_full <= irq_en_rx_full ? ~axis_read_ext_tready : 0;
        end else begin
            irq_status_tx_empty <= irq_en_tx_empty ? axis_write_ext_tvalid : 0;
            irq_status_rx_full <= irq_en_rx_full ? axis_read_tvalid : 0;
        end

        // set defaults
        fifo_rst <= 1'b0;
        axis_write_tvalid <= axis_write_tvalid_next;

        s_axil_awready_reg <= s_axil_awready_next;
        s_axil_wready_reg <= s_axil_wready_next;
        s_axil_bvalid_reg <= s_axil_bvalid_next;

        if (do_axil_write) begin
            case ({s_axil_awaddr >> 2, 2'b00})

                // Software Reset Register
                AXIL_ADDR_BASE+8'h10: begin
                    if (s_axil_wdata == 32'h0000000A) begin
                        software_rst <= 1'b1;
                    end
                end

                // SPI Control Register
                AXIL_ADDR_BASE+8'h20: begin
                    if (s_axil_wstrb[0]) begin
                        fifo_rst        <= s_axil_wdata[6];
                        mssa_reg        <= s_axil_wdata[5];
                        lsb_first_reg   <= s_axil_wdata[4];
                        cpol_reg        <= s_axil_wdata[3];
                        cpha_reg        <= s_axil_wdata[2];
                        spe_reg         <= s_axil_wdata[1];
                        loop_reg        <= s_axil_wdata[0];
                    end
                    if (s_axil_wstrb[1]) begin
                        spi_word_width_reg <= s_axil_wdata[15:8];
                    end
                    if (s_axil_wstrb[2]) begin
                        spi_clock_prescale_reg[7:0] <= s_axil_wdata[23:16];
                    end
                    if (s_axil_wstrb[3]) begin
                        spi_clock_prescale_reg[15:8] <= s_axil_wdata[31:24];
                    end
                end

                // SPI Slave Select Register
                AXIL_ADDR_BASE+8'h2C: begin
                    if (s_axil_wstrb[0]) begin
                        slave_select_reg[7:0] <= s_axil_wdata[7:0];
                    end
                    if (s_axil_wstrb[1]) begin
                        slave_select_reg[15:8] <= s_axil_wdata[15:8];
                    end
                    if (s_axil_wstrb[2]) begin
                        slave_select_reg[23:16] <= s_axil_wdata[23:16];
                    end
                    if (s_axil_wstrb[3]) begin
                        slave_select_reg[31:24] <= s_axil_wdata[31:24];
                    end
                end

                // SPI Data Transmit Register
                AXIL_ADDR_BASE+8'h30: begin
                    axis_write_tvalid <= 1'b1;

                    if (s_axil_wstrb[0]) begin
                        axis_write_tdata[7:0] <= s_axil_wdata[7:0];
                    end
                    if (s_axil_wstrb[1]) begin
                        axis_write_tdata[15:8] <= s_axil_wdata[15:8];
                    end
                    if (s_axil_wstrb[2]) begin
                        axis_write_tdata[23:16] <= s_axil_wdata[23:16];
                    end
                    if (s_axil_wstrb[3]) begin
                        axis_write_tdata[31:24] <= s_axil_wdata[31:24];
                    end
                end

                // SPI Interrupt Status Register
                AXIL_ADDR_BASE+8'h40: begin
                    if (s_axil_wdata == 32'd01) begin
                        irq_status_rx_overrun <= 0;
                        irq_status_rx_full <= 0;
                        irq_status_rx_not_empty <= 0;
                        irq_status_tx_empty <= 0;
                        irq_status_summary_last <= 0;
                    end
                end

                // SPI Interrupt Enable Register
                AXIL_ADDR_BASE+8'h44: begin
                    if (s_axil_wstrb[0]) begin
                        irq_en_rx_overrun <= s_axil_wdata[3];
                        irq_en_rx_full <= s_axil_wdata[2];
                        irq_en_rx_not_empty <= s_axil_wdata[1];
                        irq_en_tx_empty <= s_axil_wdata[0];
                    end
                end

                default: ;
            endcase
        end // do_axil_write
    end
end


/*
 * AXIL Read Transaction
 */
always @* begin
    do_axil_read = 1'b0;

    s_axil_arready_next = 1'b0;
    s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rready;

    if (s_axil_arvalid && (!s_axil_rvalid || s_axil_rready) && (!s_axil_arready)) begin
        s_axil_arready_next = 1'b1;
        s_axil_rvalid_next = 1'b1;

        do_axil_read = 1'b1;
    end
end
always @(posedge clk) begin
    if (rst || software_rst) begin
        s_axil_arready_reg <= 1'b0;
        s_axil_rvalid_reg <= 1'b0;
    end else begin
        axis_read_tready <= 1'b0;

        s_axil_arready_reg <= s_axil_arready_next;
        s_axil_rvalid_reg <= s_axil_rvalid_next;
        s_axil_rdata_reg <= 32'd0;

        if (do_axil_read) begin
            case ({s_axil_araddr >> 2, 2'b00})
                // ID Register
                AXIL_ADDR_BASE+8'h00: s_axil_rdata_reg <= 32'h294EC100;

                // Revision Register
                AXIL_ADDR_BASE+8'h04: s_axil_rdata_reg <= 32'h00000110;

                // Pointer Register
                AXIL_ADDR_BASE+8'h08: s_axil_rdata_reg <= RB_NEXT_PTR;

                // SPI Control Register
                AXIL_ADDR_BASE+8'h20: begin
                    s_axil_rdata_reg[31:16] <= spi_clock_prescale_reg;
                    s_axil_rdata_reg[15:8]  <= spi_word_width_reg;
                    s_axil_rdata_reg[5] <= mssa_reg;
                    s_axil_rdata_reg[4] <= lsb_first_reg;
                    s_axil_rdata_reg[3] <= cpol_reg;
                    s_axil_rdata_reg[2] <= cpha_reg;
                    s_axil_rdata_reg[1] <= spe_reg;
                    s_axil_rdata_reg[0] <= loop_reg;
                end

                // SPI Status Register
                AXIL_ADDR_BASE+8'h28: begin
                    // {TX_FULL, TX_EMPTY, RX_FULL, RX_EMPTY}
                    s_axil_rdata_reg[2] <= ~axis_write_ext_tvalid;
                    s_axil_rdata_reg[0] <= ~axis_read_tvalid;
                    if (FIFO_EXIST) begin
                        s_axil_rdata_reg[3] <= ~axis_write_tready;
                        s_axil_rdata_reg[1] <= ~axis_read_ext_tready;
                    end else begin
                        s_axil_rdata_reg[3] <= axis_write_ext_tvalid;
                        s_axil_rdata_reg[1] <= axis_read_tvalid;
                    end
                end

                // SPI Slave Select Register
                AXIL_ADDR_BASE+8'h2C: begin
                    s_axil_rdata_reg <= slave_select_reg;
                end

                // SPI Data Receive Register
                AXIL_ADDR_BASE+8'h34: begin
                    s_axil_rdata_reg <= axis_read_tdata;
                    axis_read_tready <= axis_read_tvalid;
                end

                // SPI Interrupt Status Register
                AXIL_ADDR_BASE+8'h40: begin
                    s_axil_rdata_reg[3] <= irq_status_rx_overrun;
                    s_axil_rdata_reg[2] <= irq_status_rx_full;
                    s_axil_rdata_reg[1] <= irq_status_rx_not_empty;
                    s_axil_rdata_reg[0] <= irq_status_tx_empty;
                end

                // SPI Interrupt Enable Register
                AXIL_ADDR_BASE+8'h44: begin
                    s_axil_rdata_reg[3] <= irq_en_rx_overrun;
                    s_axil_rdata_reg[2] <= irq_en_rx_full;
                    s_axil_rdata_reg[1] <= irq_en_rx_not_empty;
                    s_axil_rdata_reg[0] <= irq_en_tx_empty;
                end

                default: ;
            endcase
        end // do_axil_read
    end
end

/*
 * Configurations
 */

reg miso_int;
wire mosi_o_int;
wire mosi_t_int;
wire sclk_o_int;
wire sclk_t_int;


wire spi_bus_active;
reg [NUM_SS_BITS-1:0] spi_ncs_reg = {NUM_SS_BITS{1'b1}};

assign spi_ncs_o = (spe_reg) ? spi_ncs_reg : {NUM_SS_BITS{1'b1}};
assign spi_ncs_t = (spe_reg) ? spi_ncs_reg : {NUM_SS_BITS{1'b1}};

assign spi_mosi_o = (spe_reg) ? mosi_o_int : 1'b0;
assign spi_mosi_t = (spe_reg) ? mosi_t_int : 1'b0;
assign spi_sclk_o = (spe_reg) ? sclk_o_int : 1'b0;
assign spi_sclk_t = (spe_reg) ? sclk_t_int : 1'b0;

integer i;
    
always @* begin
    // set slave select (prevent multiple slaves being low)
    spi_ncs_reg = {NUM_SS_BITS{1'b1}};
    for(i=0; i < NUM_SS_BITS; i=i+1) begin
        if (slave_select_reg[i] == 0) begin
            spi_ncs_reg = {NUM_SS_BITS{1'b1}};
            spi_ncs_reg[i] = (mssa_reg) ? 0 : ~spi_bus_active;
        end
    end

    // miso location
    if (spe_reg) begin
        miso_int = (loop_reg) ? spi_mosi_o : spi_miso;
    end else begin
        miso_int = 1'b0;
    end
end

spi_master #(
    .AXIS_DATA_WIDTH(32),
    .PRESCALE_WIDTH(16)
) spi_inst (
    .clk             (clk),
    .rst             (rst | software_rst | fifo_rst),

    .sclk_o          (sclk_o_int),
    .sclk_t          (sclk_t_int),
    .mosi_o          (mosi_o_int),
    .mosi_t          (mosi_t_int),
    .miso            (miso_int),

    .enable          (spe_reg),

    // Configuration
    .lsb_first       (lsb_first_reg),
    .spi_mode        ({cpol_reg, cpha_reg}),
    .sclk_prescale   (spi_clock_prescale_reg),
    .spi_word_width  (spi_word_width_reg),

    // AXIS Input
    .s_axis_tdata    (axis_write_ext_tdata),
    .s_axis_tvalid   (axis_write_ext_tvalid),
    .s_axis_tready   (axis_write_ext_tready),

    // AXIS Output
    .m_axis_tdata    (axis_read_ext_tdata),
    .m_axis_tvalid   (axis_read_ext_tvalid),
    .m_axis_tready   (axis_read_ext_tready),

    // Status
    .rx_overrun_error(rx_overrun_error),
    .bus_active      (spi_bus_active)
);

endmodule
`resetall
