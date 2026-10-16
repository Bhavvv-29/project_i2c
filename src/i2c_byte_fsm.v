<<<<<<< HEAD
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
=======
`timescale 1ns/1ps
module i2c_byte_fsm #(
    parameter CLK_FREQ_MHZ     = 100,
    parameter CMD_HEADER_WIDTH = 4,
    parameter DATA_WIDTH       = 8,       // must be 8 (byte-oriented design)
    parameter FILTER_LEN       = 3,
    parameter GLITCH_FILTER_EN = 1
) (
    input  wire                                    clk,
    input  wire                                    rst_n,

    // command FIFO (first-word-fall-through)
    input  wire [CMD_HEADER_WIDTH+DATA_WIDTH-1:0]  cmd_in,
    input  wire                                    cmd_fifo_empty,
    output wire                                    cmd_fifo_r_en,

    // RX FIFO
    output reg  [DATA_WIDTH-1:0]                   rx_data,
    output reg                                     rx_fifo_w_en,

    // status to APB block
    input  wire                                    irq_clear,
    output wire [5:0]                              irq_status_out,
    output wire [15:0]                             tx_count,
    output wire [15:0]                             rx_count,

    // open-drain I2C bus
    input  wire                                    scl_in,
    input  wire                                    sda_in,
    output wire                                    scl_oe,
    output wire                                    sda_oe
);

    // ------------------------------------------------------------------
    // Command header encodings  (header == APB write address)
    // ------------------------------------------------------------------
    localparam [3:0] CMD_ADDRH         = 4'h0,
                     CMD_ADDRL         = 4'h1,
                     CMD_MODE          = 4'h2,
                     CMD_SCL_TIMEOUT_2 = 4'h3,
                     CMD_SCL_TIMEOUT_1 = 4'h4,
                     CMD_SCL_TIMEOUT_0 = 4'h5,
                     CMD_SDA_TIMEOUT_2 = 4'h6,
                     CMD_SDA_TIMEOUT_1 = 4'h7,
                     CMD_SDA_TIMEOUT_0 = 4'h8,
                     CMD_TX            = 4'h9,
                     CMD_RX            = 4'hA,
                     CMD_IGNORE        = 4'hF;

    // i2c_bit interface encodings (must match i2c_bit)
    localparam [2:0] TRIG_IDLE  = 3'd0,
                     TRIG_START = 3'd1,
                     TRIG_TX    = 3'd2,
                     TRIG_RX    = 3'd3,
                     TRIG_STOP  = 3'd4;

    localparam [2:0] RESP_IDLE         = 3'd0,
                     RESP_INPROGRESS   = 3'd1,
                     RESP_ARB_LOST     = 3'd2,
                     RESP_SDA_ERR      = 3'd3,
                     RESP_SDA_RECOVERY = 3'd4,
                     RESP_SCL_ERR      = 3'd5,
                     RESP_BUS_BUSY     = 3'd6;

    // irq_status_out bit positions
    localparam IRQ_NACK = 0, IRQ_ARB = 1, IRQ_SDA_ERR = 2,
               IRQ_SDA_REC = 3, IRQ_SCL_ERR = 4, IRQ_BUS_BUSY = 5;

    localparam TO_WIDTH = 3 * DATA_WIDTH;          // 24-bit timeouts

    // ------------------------------------------------------------------
    // Configuration registers
    // ------------------------------------------------------------------
    reg [1:0]          addrh;
    reg [7:0]          addrl;
    reg [2:0]          mode_reg;
    reg [TO_WIDTH-1:0] stretch_timeout;
    reg [TO_WIDTH-1:0] sda_stuck_timeout;

    wire is10 = mode_reg[0];

    // ------------------------------------------------------------------
    // Bit-level engine
    // ------------------------------------------------------------------
    reg  [2:0] trig;
    reg  [7:0] bit_tx_data;
    wire [7:0] bit_rx_data;
    wire [2:0] resp;

    i2c_bit #(
        .CLK_FREQ_MHZ    (CLK_FREQ_MHZ),
        .WIDTH           (TO_WIDTH),
        .FILTER_LEN      (FILTER_LEN),
        .GLITCH_FILTER_EN(GLITCH_FILTER_EN)
    ) u_bit (
        .clk              (clk),
        .rst_n            (rst_n),
        .trig             (trig),
        .tx_data          (bit_tx_data),
        .mode             (mode_reg[2:1]),
        .stretch_timeout  (stretch_timeout),
        .sda_stuck_timeout(sda_stuck_timeout),
        .rx_data          (bit_rx_data),
        .resp             (resp),
        .scl_in           (scl_in),
        .sda_in           (sda_in),
        .scl_oe           (scl_oe),
        .sda_oe           (sda_oe)
    );

    // ------------------------------------------------------------------
    // Command runner: one i2c_bit command at a time.
    //   go (1-cycle pulse from the FSM) -> trig held until resp==INPROGRESS
    //   -> trig=IDLE -> wait resp!=INPROGRESS -> done pulse, res/res_rx valid
    //   (res / res_rx stay valid until the next command completes)
    // ------------------------------------------------------------------
    reg        go;
    reg [2:0]  go_trig;
    reg [7:0]  go_data;

    reg        busy, ph, done;
    reg [2:0]  res;
    reg [7:0]  res_rx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trig        <= TRIG_IDLE;
            bit_tx_data <= 8'h00;
            busy        <= 1'b0;
            ph          <= 1'b0;
            done        <= 1'b0;
            res         <= RESP_IDLE;
            res_rx      <= 8'h00;
        end else begin
            done <= 1'b0;
            if (go && !busy) begin
                trig        <= go_trig;
                bit_tx_data <= go_data;
                busy        <= 1'b1;
                ph          <= 1'b0;
            end else if (busy && !ph) begin
                if (resp == RESP_INPROGRESS) begin      // command accepted
                    trig <= TRIG_IDLE;
                    ph   <= 1'b1;
                end
            end else if (busy && ph) begin
                if (resp != RESP_INPROGRESS) begin      // command finished
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    res    <= resp;
                    res_rx <= bit_rx_data;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------------
    localparam [3:0] M_IDLE  = 4'd0,   // wait for a command at the FIFO head
                     M_START = 4'd1,   // START / repeated START
                     M_ADDR1 = 4'd2,   // first address byte
                     M_ADDR2 = 4'd3,   // second address byte (10-bit)
                     M_DATA  = 4'd4,   // one TX or RX data byte
                     M_NEXT  = 4'd5,   // decide: continue / repeated START / STOP
                     M_STOP  = 4'd6,   // STOP
                     M_ERR   = 4'd7,   // record error from i2c_bit
                     M_FLUSH = 4'd8;   // discard queued TX/RX commands

    reg [3:0] state, state_n;

    reg       cur_rw,    cur_rw_n;      // 1 = read, 0 = write
    reg [7:0] cur_data,  cur_data_n;
    reg       is_rs,     is_rs_n;       // current START is a repeated START
    reg       iss,       iss_n;         // command already issued in this state
    reg       retried,   retried_n;     // SDA-recovery START retry used
    reg       err_flag,  err_flag_n;    // flush after the STOP
    reg       nack_sent, nack_sent_n;   // last RX byte was NACKed

    // FIFO head decode
    wire [CMD_HEADER_WIDTH-1:0] hdr = cmd_in[DATA_WIDTH +: CMD_HEADER_WIDTH];
    wire [DATA_WIDTH-1:0]       dat = cmd_in[DATA_WIDTH-1:0];
    wire head_valid   = ~cmd_fifo_empty;
    wire head_is_rx   = head_valid && (hdr == CMD_RX);
    wire head_is_data = head_valid && ((hdr == CMD_TX) || (hdr == CMD_RX));

    // Address bytes
    wire       rw1     = is10 ? (cur_rw & is_rs) : cur_rw;
    wire [7:0] addr_b1 = is10 ? {5'b11110, addrh, rw1} : {addrl[6:0], cur_rw};

    // combinational strobes
    reg        pop, cfg_wr, rx_push, tx_inc, rx_inc;
    reg [5:0]  irq_set;

    assign cmd_fifo_r_en = pop;

    always @* begin
        state_n     = state;
        cur_rw_n    = cur_rw;
        cur_data_n  = cur_data;
        is_rs_n     = is_rs;
        iss_n       = iss;
        retried_n   = retried;
        err_flag_n  = err_flag;
        nack_sent_n = nack_sent;

        go = 1'b0; go_trig = TRIG_IDLE; go_data = 8'h00;
        pop = 1'b0; cfg_wr = 1'b0;
        rx_push = 1'b0; tx_inc = 1'b0; rx_inc = 1'b0;
        irq_set = 6'b0;

        case (state)
            // ---------------------------------------------- IDLE
            M_IDLE: begin
                if (head_valid) begin
                    pop = 1'b1;                       // every head entry is consumed here
                    case (hdr)
                        CMD_TX, CMD_RX: begin
                            cur_rw_n   = (hdr == CMD_RX);
                            cur_data_n = dat;
                            is_rs_n    = 1'b0;
                            retried_n  = 1'b0;
                            err_flag_n = 1'b0;
                            iss_n      = 1'b0;
                            state_n    = M_START;
                        end
                        CMD_ADDRH, CMD_ADDRL, CMD_MODE,
                        CMD_SCL_TIMEOUT_2, CMD_SCL_TIMEOUT_1, CMD_SCL_TIMEOUT_0,
                        CMD_SDA_TIMEOUT_2, CMD_SDA_TIMEOUT_1, CMD_SDA_TIMEOUT_0:
                            cfg_wr = 1'b1;
                        default: ;                    // CMD_IGNORE / reserved: drop
                    endcase
                end
            end

            // ---------------------------------------------- START / repeated START
            M_START: begin
                if (!iss) begin
                    go = 1'b1; go_trig = TRIG_START; iss_n = 1'b1;
                end else if (done) begin
                    iss_n = 1'b0;
                    case (res)
                        RESP_IDLE: state_n = M_ADDR1;
                        RESP_SDA_RECOVERY: begin
                            irq_set[IRQ_SDA_REC] = 1'b1;
                            if (!retried) retried_n = 1'b1;     // stay: START again
                            else          state_n   = M_ERR;
                        end
                        default: state_n = M_ERR;
                    endcase
                end
            end

            // ---------------------------------------------- address byte 1
            M_ADDR1: begin
                if (!iss) begin
                    go = 1'b1; go_trig = TRIG_TX; go_data = addr_b1; iss_n = 1'b1;
                end else if (done) begin
                    iss_n = 1'b0;
                    if (res != RESP_IDLE) begin
                        state_n = M_ERR;
                    end else if (res_rx[0]) begin           // address NACK
                        irq_set[IRQ_NACK] = 1'b1;
                        err_flag_n = 1'b1;
                        state_n    = M_STOP;
                    end else if (!is10 || (cur_rw && is_rs)) begin
                        state_n = M_DATA;
                    end else begin
                        state_n = M_ADDR2;
                    end
                end
            end

            // ---------------------------------------------- address byte 2 (10-bit)
            M_ADDR2: begin
                if (!iss) begin
                    go = 1'b1; go_trig = TRIG_TX; go_data = addrl; iss_n = 1'b1;
                end else if (done) begin
                    iss_n = 1'b0;
                    if (res != RESP_IDLE) begin
                        state_n = M_ERR;
                    end else if (res_rx[0]) begin
                        irq_set[IRQ_NACK] = 1'b1;
                        err_flag_n = 1'b1;
                        state_n    = M_STOP;
                    end else if (cur_rw) begin              // 10-bit read: rep-START + byte1(R)
                        is_rs_n = 1'b1;
                        state_n = M_START;
                    end else begin
                        state_n = M_DATA;
                    end
                end
            end

            // ---------------------------------------------- data byte
            M_DATA: begin
                if (!iss) begin
                    go = 1'b1; iss_n = 1'b1;
                    if (cur_rw) begin
                        go_trig     = TRIG_RX;
                        go_data     = {7'b0, ~head_is_rx};  // NACK unless another RX follows
                        nack_sent_n = ~head_is_rx;
                    end else begin
                        go_trig = TRIG_TX;
                        go_data = cur_data;
                    end
                end else if (done) begin
                    iss_n = 1'b0;
                    if (res != RESP_IDLE) begin
                        state_n = M_ERR;
                    end else if (cur_rw) begin
                        rx_push = 1'b1; rx_inc = 1'b1;
                        state_n = M_NEXT;
                    end else begin
                        tx_inc = 1'b1;
                        if (res_rx[0]) begin                // data NACK from slave
                            irq_set[IRQ_NACK] = 1'b1;
                            err_flag_n = 1'b1;
                            state_n    = M_STOP;
                        end else begin
                            state_n = M_NEXT;
                        end
                    end
                end
            end

            // ---------------------------------------------- continue / RS / STOP
            M_NEXT: begin
                if (head_is_data) begin
                    pop        = 1'b1;
                    cur_data_n = dat;
                    if      (!cur_rw && hdr == CMD_TX)                state_n = M_DATA;
                    else if ( cur_rw && hdr == CMD_RX && !nack_sent)  state_n = M_DATA;
                    else begin                                        // direction change
                        cur_rw_n = (hdr == CMD_RX);
                        is_rs_n  = 1'b1;
                        state_n  = M_START;
                    end
                end else begin
                    state_n = M_STOP;
                end
            end

            // ---------------------------------------------- STOP
            M_STOP: begin
                if (!iss) begin
                    go = 1'b1; go_trig = TRIG_STOP; iss_n = 1'b1;
                end else if (done) begin
                    iss_n = 1'b0;
                    if (res != RESP_IDLE) state_n = M_ERR;
                    else                  state_n = err_flag ? M_FLUSH : M_IDLE;
                end
            end

            // ---------------------------------------------- error from i2c_bit
            M_ERR: begin
                case (res)
                    RESP_ARB_LOST:     irq_set[IRQ_ARB]      = 1'b1;
                    RESP_SDA_ERR:      irq_set[IRQ_SDA_ERR]  = 1'b1;
                    RESP_SDA_RECOVERY: irq_set[IRQ_SDA_REC]  = 1'b1;
                    RESP_SCL_ERR:      irq_set[IRQ_SCL_ERR]  = 1'b1;
                    RESP_BUS_BUSY:     irq_set[IRQ_BUS_BUSY] = 1'b1;
                    default: ;
                endcase
                state_n = M_FLUSH;
            end

            // ---------------------------------------------- drop queued data commands
            M_FLUSH: begin
                if (head_is_data) pop = 1'b1;
                else              state_n = M_IDLE;
            end

            default: state_n = M_IDLE;
        endcase
    end

    // ------------------------------------------------------------------
    // Registers, configuration, status
    // ------------------------------------------------------------------
    reg [5:0]  irq_r;
    reg [15:0] tx_cnt, rx_cnt;

    assign irq_status_out = irq_r;
    assign tx_count       = tx_cnt;
    assign rx_count       = rx_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= M_IDLE;
            cur_rw            <= 1'b0;
            cur_data          <= 8'h00;
            is_rs             <= 1'b0;
            iss               <= 1'b0;
            retried           <= 1'b0;
            err_flag          <= 1'b0;
            nack_sent         <= 1'b0;
            addrh             <= 2'b00;
            addrl             <= 8'h00;
            mode_reg          <= 3'b000;
            stretch_timeout   <= {TO_WIDTH{1'b0}};
            sda_stuck_timeout <= {TO_WIDTH{1'b0}};
            irq_r             <= 6'b0;
            tx_cnt            <= 16'h0000;
            rx_cnt            <= 16'h0000;
            rx_data           <= 8'h00;
            rx_fifo_w_en      <= 1'b0;
        end else begin
            state     <= state_n;
            cur_rw    <= cur_rw_n;
            cur_data  <= cur_data_n;
            is_rs     <= is_rs_n;
            iss       <= iss_n;
            retried   <= retried_n;
            err_flag  <= err_flag_n;
            nack_sent <= nack_sent_n;

            // configuration writes (only issued from M_IDLE)
            if (cfg_wr) begin
                case (hdr)
                    CMD_ADDRH:         addrh                     <= dat[1:0];
                    CMD_ADDRL:         addrl                     <= dat;
                    CMD_MODE:          mode_reg                  <= dat[2:0];
                    CMD_SCL_TIMEOUT_2: stretch_timeout[23:16]    <= dat;
                    CMD_SCL_TIMEOUT_1: stretch_timeout[15:8]     <= dat;
                    CMD_SCL_TIMEOUT_0: stretch_timeout[7:0]      <= dat;
                    CMD_SDA_TIMEOUT_2: sda_stuck_timeout[23:16]  <= dat;
                    CMD_SDA_TIMEOUT_1: sda_stuck_timeout[15:8]   <= dat;
                    CMD_SDA_TIMEOUT_0: sda_stuck_timeout[7:0]    <= dat;
                    default: ;
                endcase
            end

            // sticky IRQ bits: a new event wins over a simultaneous clear
            irq_r <= (irq_r & {6{~irq_clear}}) | irq_set;

            if (tx_inc) tx_cnt <= tx_cnt + 16'd1;
            if (rx_inc) rx_cnt <= rx_cnt + 16'd1;

            // RX FIFO push (1-cycle pulse)
            rx_fifo_w_en <= rx_push;
            if (rx_push) rx_data <= res_rx;
        end
    end


>>>>>>> updated hopefully
endmodule

