//i2c_byte_fsm

`timescale 1ns / 1ps


// I2C driver triggers
`define TRIG_START 3'b000
`define TRIG_TX 3'b001
`define TRIG_RX 3'b010
`define TRIG_STOP 3'b011
`define TRIG_IDLE 3'b100

// I2C driver responses 
`define RESP_IDLE 3'd0
`define RESP_INPROGRESS 3'd1
`define RESP_ARB_LOST 3'd2
`define RESP_SDA_ERR 3'd3
`define RESP_SDA_RECOVERY 3'd4
`define RESP_SCL_ERR 3'd5
`define RESP_BUS_BUSY 3'd6

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

// Read only registers
`define ADDR_RX_FIFO 16
`define ADDR_TX_COUNT_HIGH 17
`define ADDR_TX_COUNT_LOW 18

`define ADDR_RX_COUNT_HIGH 19
`define ADDR_RX_COUNT_LOW 20

`define ADDR_IRQ_STATUS 21

module i2c_byte_fsm #(
  parameter CLK_FREQ_MHZ = 100,
  parameter CMD_HEADER_WIDTH = 4,
  parameter DATA_WIDTH = 8 )(
    input wire sys_clk ,
    input wire sys_rst_n, 
    input [CMD_HEADER_WIDTH+DATA_WIDTH-1:0] cmd_in,
    input wire cmd_fifo_empty,   
    input wire rx_fifo_full, 
    input irq_clear,
    output reg cmd_fifo_r_en, 
    output reg rx_fifo_w_en,
    output reg [DATA_WIDTH -1:0] rx_out, 
    output reg [5:0] irq_status_out,
    output reg [2*DATA_WIDTH-1:0] tx_count, rx_count,
    inout wire sda,
    inout wire scl
    );
    
    reg [5:0] next_irq_status_out;
    reg [2*DATA_WIDTH-1:0] next_tx_count, next_rx_count;
    reg [DATA_WIDTH-1:0] next_rx_out;
    
    //control regs 
    reg [3*DATA_WIDTH-1:0] stretch_timeout,sda_stuck_timeout;
    reg [2:0] mode;//2-1 speed bit 0 addr type 
    reg [1:0] addrh;
    reg [7:0] addrl;
    
    // bit engine fsm instantiate 
    
    reg [2:0] trig ;
    reg [7:0] tx_buf, next_tx_buf;
    wire [7:0] rx_buf;
    wire scl_oe ;
    wire sda_oe ;
    wire [2:0] resp;
    
    i2c_bit #(.CLK_FREQ_MHZ(CLK_FREQ_MHZ),
        .WIDTH(3*DATA_WIDTH)) bit1 (.clk(sys_clk),
        .rst_n(sys_rst_n),
        .trig(trig),
        .mode(mode[2:1]),
        .stretch_timeout(stretch_timeout),
        .sda_stuck_timeout(sda_stuck_timeout),
        .tx_data(tx_buf),
        .scl_in(scl),
        .sda_in(sda),
        .scl_oe(scl_oe),
        .sda_oe(sda_oe),
        .rx_data(rx_buf),
        .resp(resp)
    );
    
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b1 : 1'bz;
    
    //pipieline command 
    

    reg [CMD_HEADER_WIDTH+DATA_WIDTH-1:0] cmd_pipeline [1:0];

    wire [CMD_HEADER_WIDTH-1:0] cmd0,cmd1;
    wire [DATA_WIDTH-1:0] cmd_data0,cmd_data1;

    reg pipeline_advance;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            cmd_fifo_r_en <= 1'b0;
            cmd_pipeline[1] <= {`CMD_IGNORE,{DATA_WIDTH{1'b0}}};
            cmd_pipeline[0] <= {`CMD_IGNORE,{DATA_WIDTH{1'b0}}};   
        end 
        else begin
            cmd_fifo_r_en <= 1'b0;
            if(pipeline_advance) begin
                cmd_pipeline[0] <= cmd_pipeline[1];
                cmd_pipeline[1] <= cmd_fifo_empty ? {`CMD_IGNORE, {DATA_WIDTH{1'b0}}} : cmd_in;
                cmd_fifo_r_en <= cmd_fifo_empty ? 1'b0: 1'b1;
            end 
            else begin
              cmd_fifo_r_en <= 1'b0;
              if(pipeline_advance)begin   
                //if(cmd[0]==`CMD_IGNORE) begin
                    cmd_pipeline[0] <= cmd_pipeline[1];
                    cmd_pipeline[1] <= cmd_fifo_empty ? {`CMD_IGNORE, {DATA_WIDTH{1'b0}}} : cmd_in;
                    cmd_fifo_r_en <= cmd_fifo_empty ? 1'b0 : 1'b1;
                end 
                else begin 
                  if (cmd0 == `CMD_IGNORE) begin 
                    cmd_pipeline[0] <= cmd_pipeline[1];
                    cmd_pipeline[1] <= cmd_fifo_empty ? {`CMD_IGNORE, {DATA_WIDTH{1'b0}}}:cmd_in;
                    cmd_fifo_r_en <= cmd_fifo_empty ? 1'b0 : 1'b1;
                  end 
            end
        end
    end
    end 
     

    
    assign cmd0 = cmd_pipeline[0][CMD_HEADER_WIDTH+DATA_WIDTH-1:DATA_WIDTH];
    assign cmd_data0 = cmd_pipeline[0][DATA_WIDTH-1:0];

    assign cmd1 = cmd_pipeline[1][CMD_HEADER_WIDTH+DATA_WIDTH-1:DATA_WIDTH];
   // assign cmd_data1 = cmd_pipeline[1][DATA_WIDTH-1:0];


//byte level fsm 

reg [3:0] state , next_state ;
localparam [3:0] IDLE =4'd0,
      READ_CMD = 4'd1,
      LOAD = 4'd2,
      START = 4'd3,
      ADDR1 = 4'd4,
      ADDR2 = 4'd5,
      TX_DATA = 4'd6,
      RX_DATA = 4'd7,
      STOP = 4'd8,
      ERROR_STICKY = 4'd9;
      
      reg addr_10_addressed;
      reg next_addr_10_addressed;
      
      reg [2:0] byte_idx, next_byte_idx;
      reg wait_resp;
      
      always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin 
          state <= IDLE ;
          byte_idx <= 3'd0;
          addr_10_addressed <= 1'b0;
          tx_buf <= 8'd0;
          rx_out <= {DATA_WIDTH {1'b0}};
          irq_status_out <= 6'd0;
          tx_count <= {(2* DATA_WIDTH){1'b0}};
          rx_count <= {(2*DATA_WIDTH ) {1'b0}};
          wait_resp <= 1'b0;        
        end 
        else begin 
          state <= wait_resp? state : next_state ;
          byte_idx <= next_byte_idx;
          addr_10_addressed <= next_addr_10_addressed;
          tx_buf <= next_tx_buf;
          rx_out <= next_rx_out ;
          irq_status_out <= next_irq_status_out;
          tx_count <= next_tx_count ;
          rx_count <= next_rx_count ;
          wait_resp <= (trig != `TRIG_IDLE);          
          
          if (state == LOAD ) begin 
            case (cmd0) 
                `CMD_ADDRH: addrh <= cmd_data0[1:0];
                `CMD_ADDRL: addrl <= cmd_data0[7:0];
                `CMD_MODE: mode <= cmd_data0[2:0];
                `CMD_SCL_TIMEOUT_2: stretch_timeout <= {cmd_data0, stretch_timeout[2*DATA_WIDTH-1:0]};
                `CMD_SCL_TIMEOUT_1: stretch_timeout <= {stretch_timeout[3*DATA_WIDTH-1:2*DATA_WIDTH], cmd_data0, stretch_timeout[DATA_WIDTH-1:0]};
                `CMD_SCL_TIMEOUT_0: stretch_timeout <= {stretch_timeout[3*DATA_WIDTH-1:DATA_WIDTH], cmd_data0};

                `CMD_SDA_TIMEOUT_2: sda_stuck_timeout <= {cmd_data0, sda_stuck_timeout[2*DATA_WIDTH-1:0]};
                `CMD_SDA_TIMEOUT_1: sda_stuck_timeout <= {sda_stuck_timeout[3*DATA_WIDTH-1:2*DATA_WIDTH], cmd_data0, sda_stuck_timeout[DATA_WIDTH-1:0]};
                `CMD_SDA_TIMEOUT_0: sda_stuck_timeout <= {sda_stuck_timeout[3*DATA_WIDTH-1:DATA_WIDTH], cmd_data0};
               // default : ;
            endcase
        end
    end 
  end 
        
        always @(*) begin 
          rx_fifo_w_en = 1'b0;
          next_state = state ;
          trig = `TRIG_IDLE ;
          next_tx_buf = tx_buf ;
          next_addr_10_addressed = addr_10_addressed;
          next_irq_status_out = irq_status_out;
          pipeline_advance =1'b0;
          next_rx_out = rx_out ;
          next_byte_idx = byte_idx;
          next_rx_count = rx_count ;
          next_tx_count = tx_count ;
        
        case(resp) 
          `RESP_ARB_LOST: begin
            next_irq_status_out[4] = 1'b1;
            next_state = ERROR_STICKY;
          end
          `RESP_SDA_ERR, `RESP_SDA_RECOVERY: begin
            next_irq_status_out[0] = 1'b1;
              next_state = IDLE;
          end
          `RESP_BUS_BUSY: begin
            next_irq_status_out[1] = 1'b1;
            next_state = IDLE;
          end
          `RESP_SCL_ERR: begin
            if (state == TX_DATA || state == RX_DATA)
              next_irq_status_out[2] = 1'b1;
            else
                next_irq_status_out[3] = 1'b1;
            next_state = IDLE;
          end
          default: begin
            case(state)
              IDLE: begin
                next_irq_status_out[4:1] = 4'b0;
                next_state = (cmd0!=`CMD_IGNORE) ? READ_CMD : IDLE;
                next_addr_10_addressed = 1'b0;
                next_byte_idx = 3'b0;
              end
              READ_CMD: begin
                if(cmd0 ==`CMD_TX || cmd0==`CMD_RX) begin
                  next_state = START;
                  trig = `TRIG_START;
                  end
                  else begin
                    next_state = LOAD;
                  end
               end
               LOAD: begin
                next_state = IDLE;
                trig = `TRIG_IDLE;
                pipeline_advance = 1'b1;
               end
               
               START: begin
                if(resp==`RESP_IDLE) begin
                  trig = `TRIG_TX;
                  next_state = ADDR1;          
                  if(cmd0==`CMD_TX) begin
                    if(mode[0]) 
                      next_tx_buf = {5'b11110, addrh, 1'b0};
                    else
                      next_tx_buf = {addrl[6:0], 1'b0};
                  end
                  else begin
                    if(mode[0])     
                      next_tx_buf = addr_10_addressed ? {5'b11110, addrh, 1'b1} : {5'b11110, addrh, 1'b0};
                    else
                      next_tx_buf = {addrl[6:0], 1'b1};
                  end
                end
              end
              ADDR1: begin
                if(resp==`RESP_IDLE) begin
                  if(rx_buf[7]) begin
                    next_state = STOP;
                    trig = `TRIG_STOP;
                    next_irq_status_out[5] = 1'b1;
                  end 
                  else begin
                    if(mode[0] && !addr_10_addressed) begin
                      next_state = ADDR2;
                      trig = `TRIG_TX;
                      next_tx_buf = addrl;
                    end 
                    else begin
                      //next_state = (cmd0==`CMD_TX) ? TX_DATA : RX_DATA;
                      if(cmd0==`CMD_TX) begin
                        next_state = TX_DATA;
                        trig = `TRIG_TX;
                        next_tx_buf = cmd_data0[DATA_WIDTH-(8*byte_idx)-1 -: 8];
                        next_byte_idx = byte_idx+1'b1;
                      end 
                      else begin
                        next_state = RX_DATA;
                        trig = `TRIG_RX;
                      end
                      end
                    end
                    end 
                    end
                    ADDR2: begin
                      if(resp==`RESP_IDLE) begin
                        if(rx_buf[7]) begin
                          next_state = STOP;
                          trig = `TRIG_STOP;
                          next_irq_status_out[5] = 1'b1;
                        end else begin
                          next_addr_10_addressed = 1'b1;
                          if(cmd0==`CMD_TX) begin
                            next_state = TX_DATA;
                            trig = `TRIG_TX;
                            next_tx_buf = cmd_data0[DATA_WIDTH-(8*byte_idx)-1 -: 8];
                            next_byte_idx = byte_idx+1;
                          end 
                          else begin
                            next_state = START;
                            trig = `TRIG_START;
                          end
                        end
                      end 
                    end
                    TX_DATA: begin
                        if(resp==`RESP_IDLE) begin
                            if(rx_buf[7]) begin
                                next_state = STOP;
                                trig = `TRIG_STOP;
                                next_irq_status_out[5] = 1'b1;
                            end else begin
                                if((DATA_WIDTH/8) > byte_idx) begin
                                    next_state = TX_DATA;
                                    trig = `TRIG_TX;
                                    next_tx_buf = cmd_data0 [DATA_WIDTH-(8*byte_idx)-1 -: 8];
                                    next_byte_idx = byte_idx+1;
                                end else begin
                                    next_byte_idx = 3'b0;
                                    next_tx_count = tx_count+1;
                                    pipeline_advance = 1'b1;
                                    

                                    if(cmd1==`CMD_TX) begin
                                        next_state = TX_DATA;
                                        trig = `TRIG_TX;
                                    end else if(cmd1==`CMD_RX) begin
                                        next_state = START;
                                        trig = `TRIG_START;
                                    end else begin
                                        next_state = STOP;
                                        trig = `TRIG_STOP;
                                    end
                                end
                            end
                        end 
                    end
                    RX_DATA: begin
                        next_tx_buf = (cmd1!=`CMD_RX && byte_idx==(DATA_WIDTH/8)-1) ? 8'b1000_0000 : 8'b0;
                        if(resp==`RESP_IDLE) begin
                            if((DATA_WIDTH/8) > byte_idx) begin
                                next_state = RX_DATA;
                                trig = `TRIG_RX;
                                next_rx_out[DATA_WIDTH-(8*byte_idx)-1 -: 8] = rx_buf;
                                next_byte_idx = byte_idx+1;
                            end else begin
                                next_byte_idx = 3'b0;
                                next_rx_count = rx_count+1;
                                pipeline_advance = 1'b1;
                                rx_fifo_w_en = !rx_fifo_full;        

                                if(cmd1==`CMD_RX) begin
                                    next_state = RX_DATA;
                                    trig = `TRIG_RX;
                                end else if(cmd1==`CMD_TX) begin
                                    next_state = START;
                                    trig = `TRIG_START;                            
                                end else begin
                                    next_state = STOP;
                                    trig = `TRIG_STOP;
                                end
                            end
                        end
                    end
                    STOP: begin
                        if(resp==`RESP_IDLE) 
                            next_state = irq_status_out[5] ? ERROR_STICKY : IDLE;
                            
                    end
                    ERROR_STICKY: begin
                        if(irq_clear) begin
                            next_irq_status_out[4] = 1'b0;
                            next_irq_status_out[5] = 1'b0;
                            next_state = IDLE;
                        end
                    end
                endcase
            end
        endcase
    end
endmodule

