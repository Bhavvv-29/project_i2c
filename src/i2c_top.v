`timescale 1ns/1ps
module i2c_top #(
    parameter CLK_FREQ_MHZ     = 100,
    parameter FILTER_LEN       = 3,
    parameter GLITCH_FILTER_EN = 1,
    parameter CMD_FIFO_DEPTH   = 1024,
    parameter RX_FIFO_DEPTH    = 1024
) (
    // APB4 slave
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire [4:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PWDATA,
    output wire [7:0]  PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // interrupt
    output wire        irq,

    // open-drain I2C bus
    inout  wire        scl,
    inout  wire        sda
);

    // ------------------------------------------------------------------
    // Register offsets (must match i2c_byte_fsm's CMD_* header encoding for
    // 0x00-0x0A: the command word pushed to the FIFO is {PADDR[3:0], PWDATA}).
    // ------------------------------------------------------------------
    localparam [4:0] ADDR_SLV_ADDRH   = 5'h00,
                     ADDR_SLV_ADDRL   = 5'h01,
                     ADDR_MODE        = 5'h02,
                     ADDR_SCL_TO2     = 5'h03,
                     ADDR_SCL_TO1     = 5'h04,
                     ADDR_SCL_TO0     = 5'h05,
                     ADDR_SDA_TO2     = 5'h06,
                     ADDR_SDA_TO1     = 5'h07,
                     ADDR_SDA_TO0     = 5'h08,
                     ADDR_TX_DATA     = 5'h09,
                     ADDR_RX_DATA_CMD = 5'h0A,   // write-a-command offset (issues CMD_RX)
                     ADDR_IRQ_CLEAR   = 5'h0B,
                     ADDR_RX_FIFO     = 5'h10,   // read-the-data offset (pops RX FIFO)
                     ADDR_TXCNT_HI    = 5'h11,
                     ADDR_TXCNT_LO    = 5'h12,
                     ADDR_RXCNT_HI    = 5'h13,
                     ADDR_RXCNT_LO    = 5'h14,
                     ADDR_IRQ_STATUS  = 5'h15;

    localparam [4:0] LAST_WRITABLE = ADDR_IRQ_CLEAR;   // 0x0B: highest defined write offset

    // ------------------------------------------------------------------
    // APB4 transfer qualifiers (zero-wait-state slave: PREADY tied high, so
    // PSEL & PENABLE is exactly the one-cycle ACCESS phase of every transfer)
    // ------------------------------------------------------------------
    wire apb_access = PSEL & PENABLE;
    wire apb_write  = apb_access & PWRITE;
    wire apb_read   = apb_access & ~PWRITE;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // ------------------------------------------------------------------
    // Command FIFO write-side decode
    // ------------------------------------------------------------------
    wire        cmd_write = apb_write & (PADDR <= LAST_WRITABLE) & (PADDR != ADDR_IRQ_CLEAR);
    wire [11:0] cmd_word  = {PADDR[3:0], PWDATA};

    wire irq_clear_pulse = apb_write & (PADDR == ADDR_IRQ_CLEAR);

    // ------------------------------------------------------------------
    // Illegal-access decode (see header comment for the design decision)
    // ------------------------------------------------------------------
    wire addr_readable = (PADDR >= ADDR_RX_FIFO) && (PADDR <= ADDR_IRQ_STATUS);
    wire illegal_write = apb_write & (PADDR > LAST_WRITABLE);
    wire illegal_read  = apb_read  & ~addr_readable;
    wire illegal_event = illegal_write | illegal_read;

    // ------------------------------------------------------------------
    // Command FIFO (APB -> i2c_byte_fsm)
    // ------------------------------------------------------------------
    wire [11:0] cmd_fifo_r_data;
    wire        cmd_fifo_empty, cmd_fifo_full, cmd_fifo_r_en;
    wire        cmd_fifo_w_en = cmd_write & ~cmd_fifo_full;
    wire        cmd_fifo_ovf_event = cmd_write & cmd_fifo_full;   // -> IRQ_STATUS[6]

    i2c_fifo #(.WIDTH(12), .DEPTH(CMD_FIFO_DEPTH)) u_cmd_fifo (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .w_en     (cmd_fifo_w_en),
        .w_data   (cmd_word),
        .r_en     (cmd_fifo_r_en),
        .r_data   (cmd_fifo_r_data),
        .full     (cmd_fifo_full),
        .empty    (cmd_fifo_empty),
        .count    (),
        .overflow (),
        .underflow()
    );

    // ------------------------------------------------------------------
    // RX FIFO (i2c_byte_fsm -> APB)
    // ------------------------------------------------------------------
    wire [7:0] rx_fifo_w_data, rx_fifo_r_data;
    wire       rx_fifo_w_en, rx_fifo_empty;
    wire       rx_fifo_r_en = apb_read & (PADDR == ADDR_RX_FIFO);

    i2c_fifo #(.WIDTH(8), .DEPTH(RX_FIFO_DEPTH)) u_rx_fifo (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .w_en     (rx_fifo_w_en),
        .w_data   (rx_fifo_w_data),
        .r_en     (rx_fifo_r_en),
        .r_data   (rx_fifo_r_data),
        .full     (),
        .empty    (rx_fifo_empty),
        .count    (),
        .overflow (),
        .underflow()
    );

  
    wire scl_oe, sda_oe;
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;
    wire scl_in = scl;
    wire sda_in = sda;

    // ------------------------------------------------------------------
    // Byte-level sequencer + bit-level engine
    // ------------------------------------------------------------------
    wire [5:0]  byte_irq_status;
    wire [15:0] tx_count, rx_count;

    i2c_byte_fsm #(
        .CLK_FREQ_MHZ    (CLK_FREQ_MHZ),
        .CMD_HEADER_WIDTH(4),
        .DATA_WIDTH      (8),
        .FILTER_LEN      (FILTER_LEN),
        .GLITCH_FILTER_EN(GLITCH_FILTER_EN)
    ) u_byte_fsm (
        .clk           (PCLK),
        .rst_n         (PRESETn),
        .cmd_in        (cmd_fifo_r_data),
        .cmd_fifo_empty(cmd_fifo_empty),
        .cmd_fifo_r_en (cmd_fifo_r_en),
        .rx_data       (rx_fifo_w_data),
        .rx_fifo_w_en  (rx_fifo_w_en),
        .irq_clear     (irq_clear_pulse),
        .irq_status_out(byte_irq_status),
        .tx_count      (tx_count),
        .rx_count      (rx_count),
        .scl_in        (scl_in),
        .sda_in        (sda_in),
        .scl_oe        (scl_oe),
        .sda_oe        (sda_oe)
    );


    reg fifo_full_sticky, illegal_sticky;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            fifo_full_sticky <= 1'b0;
            illegal_sticky   <= 1'b0;
        end else begin
            fifo_full_sticky <= (fifo_full_sticky & ~irq_clear_pulse) | cmd_fifo_ovf_event;
            illegal_sticky   <= (illegal_sticky   & ~irq_clear_pulse) | illegal_event;
        end
    end

    wire [7:0] irq_status_full = {illegal_sticky, fifo_full_sticky, byte_irq_status};

    assign irq = |irq_status_full;

    // ------------------------------------------------------------------
    // Read mux
    // ------------------------------------------------------------------
    reg [7:0] prdata_r;
    always @* begin
        case (PADDR)
            ADDR_RX_FIFO:    prdata_r = rx_fifo_r_data;
            ADDR_TXCNT_HI:   prdata_r = tx_count[15:8];
            ADDR_TXCNT_LO:   prdata_r = tx_count[7:0];
            ADDR_RXCNT_HI:   prdata_r = rx_count[15:8];
            ADDR_RXCNT_LO:   prdata_r = rx_count[7:0];
            ADDR_IRQ_STATUS: prdata_r = irq_status_full;
            default:         prdata_r = 8'h00;   // write-only, reserved, or unmapped
        endcase
    end
    assign PRDATA = prdata_r;

  

endmodule

