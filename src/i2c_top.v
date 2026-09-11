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


