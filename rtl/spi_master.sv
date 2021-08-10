`timescale 1ns / 1ps
//NOTE: Enable is currently not tied to the tx and rx modules, I will decide on how to tie it in once I make tx changes
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
    output wire                  rx_overrun_error,
    output wire                  bus_active
);

reg sclk_buff = 0;
reg sclk_en = 0; //Figure out when to toggle enable/what determines toggling
reg [7:0] sclk_prescale_buff;
reg [1:0] spi_mode_buff;
reg [7:0] prescale_counter;
reg [7:0] busy_counter = 0;

reg active = 0;

assign cpol = (spi_mode_buff === 2) | (spi_mode_buff === 3);
assign cpha = (spi_mode_buff === 1) | (spi_mode_buff === 2);

assign bus_active = active;



assign sclk = sclk_buff;

enum reg [1:0] {IDLE, TX_WAIT, RX_WAIT} master_state = IDLE;

always_ff @(posedge clk) begin : proc_SCLK
    if (rst) begin
        prescale_counter <= 0;
    end else begin
        if (sclk_en) begin
            prescale_counter <= prescale_counter + 1;
            if (prescale_counter == sclk_prescale_buff >> 1) begin
                sclk_buff <= !sclk_buff;
                prescale_counter <= 0;
            end
        end
        else begin
            sclk_buff <= cpol;
        end   
    end
end

always_ff @(negedge clk) begin // BUSY detection
    if (rst) begin
        busy_counter <= 0;
        master_state <= IDLE;
    end
    case (master_state)
        IDLE: begin // Waits to catch tx_busy == 1
            sclk_prescale_buff <= sclk_prescale;
            spi_mode_buff <= spi_mode;
            if (tx_busy) begin
                active <= 1;
                master_state <= TX_WAIT;
            end
        end
        TX_WAIT: begin //Waits one SCLK by counting busy_counter, then pulls sclk_en high
            busy_counter <= busy_counter + 1;
            if (busy_counter == sclk_prescale_buff - 1)
                sclk_en <= 1; // NOTE: Since both SCLK generation and BUSY detection are both posedge sensitive, at least one CLK cycle will elapse before sclk generation begins.
            if (rx_busy) begin
                busy_counter <= 0;
                master_state <= RX_WAIT;
            end
        end
        RX_WAIT: begin //When !rx_busy gets detected, pulls sclk_en low and then counts for one SCLK
            if (!rx_busy || !sclk_en) begin //NOTE: Could be problematic; if rx_busy does not remain low for at least one SCLK, state machine would get stuck in this state. One solution is to split it into two states, like IDLE and TX_WAIT
                sclk_en <= 0; //NOTE: Same problem as stated in TX_WAIT
                busy_counter <= busy_counter + 1;
                if (busy_counter == sclk_prescale_buff - 1) begin 
                    active <= 0;
                    busy_counter <= 0;
                end
                if (!active) begin
                    busy_counter <= busy_counter + 1;
                    if (busy_counter == sclk_prescale_buff - 1) begin
                        master_state <= IDLE; // Returns to IDLE to wait for the next tx_busy
                        busy_counter <= 0;
                    end
                end
            end
        end
    endcase
end
spi_rx #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
) spi_rx_inst (
    .clk(clk),
    .rst(rst),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),

    .enable_capture(bus_active),

    .sclk          (sclk_buff),
    .rxd           (miso),


    .spi_mode      (spi_mode),
    .spi_word_width(spi_word_width),

    .busy          (rx_busy),
    .overrun_error (rx_overrun_error)
);

spi_tx #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
) spi_tx_inst (
    .sclk(sclk_buff),
    .clk(clk),
    .rst(rst),

    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),

    .txd           (mosi),
    .tx_enable     (bus_active),

    .spi_mode      (spi_mode),
    .spi_word_width(spi_word_width),

    .busy          (tx_busy)
);

endmodule : spi_master
