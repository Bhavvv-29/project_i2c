<<<<<<< HEAD
//i2c_top

`timescale 1ns / 1ps

`define ADDR_RX_FIFO 16
`define ADDR_TX_COUNT_HIGH 17
`define ADDR_TX_COUNT_LOW 18

`define ADDR_RX_COUNT_HIGH 19
`define ADDR_RX_COUNT_LOW 20

`define ADDR_IRQ_STATUS 21

// APB Commands
`define CMD_ADDRH 4'b0000
`define CMD_ADDRL 4'b0001
`define CMD_MODE 4'b0010
`define CMD_SCL_TIMEOUT_2 4'b0011
`define CMD_SCL_TIMEOUT_1 4'b0100
`define CMD_SCL_TIMEOUT_0 4'b0101
`define CMD_SDA_TIMEOUT_2 4'b0110
`define CMD_SDA_TIMEOUT_1 4'b0111
`define CMD_SDA_TIMEOUT_0 4'b1000
`define CMD_TX 4'b1001
`define CMD_RX 4'b1010
`define CMD_IGNORE 4'b1011

// APB Addresses
// Write only
`define ADDR_I2C_SLV_ADDRH 0
`define ADDR_I2C_SLV_ADDRL 1
`define ADDR_MODE 2
`define ADDR_SCL_TIMEOUT2 3
`define ADDR_SCL_TIMEOUT1 4
`define ADDR_SCL_TIMEOUT0 5

`define ADDR_SDA_TIMEOUT2 6
`define ADDR_SDA_TIMEOUT1 7
`define ADDR_SDA_TIMEOUT0 8

`define ADDR_TX_DATA 9
`define ADDR_RX_DATA 10
`define ADDR_IRQ_CLEAR 11

module i2c_top #(parameter PCLK_FREQ_MHZ=100,
    parameter ADDR_WIDTH = 5,
    parameter CMD_WIDTH = 12,
    parameter DATA_WIDTH = 8, 
    parameter FIFO_DEPTH = 2048)(
      input wire PCLK,
      input wire PRESETn,
      input wire [ADDR_WIDTH-1:0] PADDR,
      input wire PSEL,
      input wire PENABLE,
      input wire PWRITE,
      input [DATA_WIDTH-1 :0] PWDATA,
      
      output wire PREADY,
      output wire PSLVERR,
      output reg [DATA_WIDTH-1:0] PRDATA,
      
      input scl,sda
    );
    
    //read onyl apb registers 
    wire [2*DATA_WIDTH -1:0] tx_count , rx_count;
    wire [7:0] irq_status;
    
    //CMD and rx fifo 
    
    wire cmd_fifo_empty, rx_fifo_full;
    wire cmd_fifo_full, rx_fifo_empty ;
    reg cmd_fifo_w_en;
    reg [CMD_WIDTH-DATA_WIDTH-1:0] cmd;
    wire [DATA_WIDTH -1:0] rx_fifo_rdata;
    wire irq_clear;
    
    i2c_fifo  #(
        .WIDTH(CMD_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_cmd_fifo(
        .clk(PCLK),
        .rst_n(PRESETn),
        .r_en(cmd_fifo_r_en),
        .w_en(cmd_fifo_w_en),
        .data_in({cmd, PWDATA}),
        .data_out(i2c_cmd),
        .full(cmd_fifo_full),
        .empty(cmd_fifo_empty)
    );


    i2c_fifo #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_rx_fifo(
        .clk(PCLK),
        .rst_n(PRESETn),
        .r_en(PSEL && PENABLE && !PWRITE && (PADDR==`ADDR_RX_FIFO) && !rx_fifo_empty),
        .w_en(rx_fifo_w_en),
        .data_in(i2c_rx_data),
        .data_out(rx_fifo_rdata),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty)
    );
    
        i2c_byte_fsm #(
        .CLK_FREQ_MHZ (PCLK_FREQ_MHZ),
        .CMD_HEADER_WIDTH (CMD_WIDTH- DATA_WIDTH),  
        .DATA_WIDTH (DATA_WIDTH)      
    ) u_i2c_master (
        .sys_clk(PCLK),
        .sys_rst_n(PRESETn),
        .cmd_fifo_empty(cmd_fifo_empty),
        //.rx_fifo_full(rx_fifo_full),
        .cmd_in(i2c_cmd),     
        .cmd_fifo_r_en(cmd_fifo_r_en),     
        .rx_fifo_w_en(rx_fifo_w_en),      
        .rx_out(i2c_rx_data),      
        .irq_status_out(irq_status[5:0]),
        .irq_clear(irq_clear),
        .tx_count(tx_count),
        .rx_count(rx_count),
        .scl(scl),
        .sda(sda)
    );
    
     // Interrupts and error handling -----------------------------------------------------------------------------------------
    assign irq_status[6] = cmd_fifo_full;                                                               // interrupt for cmd fifo full 
    assign irq_status[7] = (PSEL && PENABLE) && ((PWRITE && PADDR[4]) || (!PWRITE && !PADDR[4]));       // interrupt for illegal access 


    assign irq_clear = (PSEL && PENABLE && PWRITE) && (PADDR==`ADDR_IRQ_CLEAR);

    assign PSLVERR = (PSEL && PENABLE) && (|irq_status);

    // APB address decoder -----------------------------------------------------------------------------------------------------
    always @(*) begin
        cmd_fifo_w_en = 1'b0;
        cmd = `CMD_IGNORE;
        PRDATA = {DATA_WIDTH{1'b0}};
        
        if(PSEL && PENABLE) begin
            if(PWRITE) begin
                if(!cmd_fifo_full) begin
                    cmd_fifo_w_en = 1'b1;
                    case(PADDR)
                        `ADDR_I2C_SLV_ADDRH: cmd = `CMD_ADDRH;
                        `ADDR_I2C_SLV_ADDRL: cmd = `CMD_ADDRL;
                        `ADDR_MODE: cmd = `CMD_MODE;
                        `ADDR_SCL_TIMEOUT2: cmd = `CMD_SCL_TIMEOUT_2;
                        `ADDR_SCL_TIMEOUT1: cmd = `CMD_SCL_TIMEOUT_1;
                        `ADDR_SCL_TIMEOUT0: cmd = `CMD_SCL_TIMEOUT_0;
                        `ADDR_SDA_TIMEOUT2: cmd = `CMD_SDA_TIMEOUT_2;
                        `ADDR_SDA_TIMEOUT1: cmd = `CMD_SDA_TIMEOUT_1;
                        `ADDR_SDA_TIMEOUT0: cmd = `CMD_SDA_TIMEOUT_0;
                        `ADDR_TX_DATA: cmd = `CMD_TX;
                        `ADDR_RX_DATA: cmd = `CMD_RX;
                        default: cmd_fifo_w_en = 1'b0;
                    endcase
                end else begin
                    cmd_fifo_w_en = 1'b0;
                end
            end else begin
                case(PADDR)
                    `ADDR_RX_FIFO: begin
                        PRDATA = rx_fifo_empty ? {DATA_WIDTH{1'b0}} : rx_fifo_rdata;
                    end
                    `ADDR_TX_COUNT_HIGH:
                        PRDATA = tx_count[(2*DATA_WIDTH)-1:DATA_WIDTH];

                    `ADDR_TX_COUNT_LOW:
                        PRDATA = tx_count[DATA_WIDTH-1:0];

                    `ADDR_RX_COUNT_HIGH:
                        PRDATA = rx_count[(2*DATA_WIDTH)-1:DATA_WIDTH];

                    `ADDR_RX_COUNT_LOW:
                        PRDATA = rx_count[DATA_WIDTH-1:0];

                    `ADDR_IRQ_STATUS:
                        PRDATA = {{(DATA_WIDTH-8){1'b0}}, irq_status};

                    default:
                        PRDATA = {DATA_WIDTH{1'b0}};
                endcase
            end
        end
    end
    
    assign PREADY = 1'b1;

    // -------------------------------------------------------------------------------------------------------------------------
    
endmodule

=======
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
>>>>>>> updated hopefully

