//i2c_bit

`timescale 1ns / 1ps


//timign 
//Std(100kHz) 
`define T_STA_SU_STD 4700
`define T_STA_HD_STD 4000 
`define T_LOW_STD 6000
`define T_HIGH_STD 4000
`define T_STO_SU_STD 4000
`define T_BUF_STD 4700
`define T_RECOVERY_HALF_CYCLE_STD 5000

// Fast (400 kHz)
`define T_STA_SU_FAST 600
`define T_STA_HD_FAST 600
`define T_LOW_FAST 1500
`define T_HIGH_FAST 1000
`define T_STO_SU_FAST 600
`define T_BUF_FAST 1300     
`define T_RECOVERY_HALF_CYCLE_FAST 1250

//FAST PLUS (1MHz) 
`define T_STA_SU_FASTP 260
`define T_STA_HD_FASTP 260
`define T_LOW_FASTP 600
`define T_HIGH_FASTP 400
`define T_STO_SU_FASTP 260
`define T_BUF_FASTP 500
`define T_RECOVERY_HALF_CYCLE_FASTP 500


`define ns_to_cyc(CLK_FREQ_MHZ, NS) (((CLK_FREQ_MHZ * NS)/1000) + 1)

module i2c_bit #(
    parameter integer CLK_FREQ_MHZ = 100,
    //parameter integer MODE = 1,
    parameter integer WIDTH = 24
)(
    input wire clk,
    input wire rst_n,
    input [1:0] mode,
    input [2:0] trig,
    
    input [WIDTH -1 : 0]stretch_timeout,
    input [WIDTH -1 : 0]sda_stuck_timeout,
    
    input wire [7:0] tx_data,
    input wire scl_in,
    input wire sda_in,
    
    output reg sda_oe , 
    output reg scl_oe,
    
    output reg [7:0] rx_data,
    output reg [2:0] resp
);

//synchronize the inputs scl and sda 
wire scl_syn;
wire sda_syn;

sync_2ff s1 (.clk(clk),.rst_n(rst_n),.din(scl_in),.dout(scl_syn));
sync_2ff s2 (.clk(clk),.rst_n(rst_n),.din(sda_in),.dout(sda_syn));


//fsm states 

    localparam [3:0]
        IDLE       = 4'd0,
        START_SU   = 4'd1,
        START_HOLD = 4'd2,
        TX_LOW     = 4'd3,
        TX_HIGH    = 4'd4,
        RX_LOW     = 4'd5,
        RX_HIGH    = 4'd6,
        STOP_LOW   = 4'd7,
        STOP_SU    = 4'd8,
        STOP_HOLD  = 4'd9,
        BUS_BUSY   = 4'd10,
        BUS_BUFF   = 4'd11,
        SDA_RECOVERY = 4'd12;

    
    
    //resp codes 
    
    localparam [2:0] RESP_IDLE =3'd0,
                     RESP_INPROGRESS = 3'd1,
                     RESP_BUS_BUSY = 3'd2,
                     RESP_ARB_LOST = 3'd3,
                     RESP_SDA_RECOVERY = 3'd4,
                     RESP_SDA_ERR = 3'd5,
                     RESP_SCL_ERR = 3'd6 ;
          
    reg [3:0] state, next_state ;
  
    localparam CNT_WIDTH = $clog2 (`ns_to_cyc(CLK_FREQ_MHZ,6000));
    
    reg [CNT_WIDTH-1:0] count_value;
    reg count_en;
    wire count_done;
    reg running ;
    
    //error flags 
    wire scl_error;
    wire sda_error;
    
   i2c_counter #(.CNT_WIDTH(CNT_WIDTH)) u_ctr_main (
        .clk(clk),
        .rst_n(rst_n),
        .en(count_en),
        .max_count(count_value),
        .done(count_done)
    );
    
    //clock strech and sda stuck error detection 
    reg [WIDTH-1:0] stretch_cnt ;
    always @(posedge clk or negedge rst_n) begin 
      if (!rst_n) stretch_cnt <= {WIDTH{1'b0}};
      else if (!scl_oe && !scl_syn && running) stretch_cnt <= stretch_cnt +1'b1;
      else stretch_cnt <= {WIDTH {1'b0}};
    end 
    assign scl_error = (stretch_cnt >= stretch_timeout);
    
    reg [WIDTH-1:0] sda_stuck_cnt;
    always @(posedge clk or negedge rst_n) begin 
      if (!rst_n) 
        sda_stuck_cnt <= {WIDTH{1'b0}};
      else if (!sda_oe && !sda_syn && state == IDLE ) 
        sda_stuck_cnt <= sda_stuck_cnt + 1'b1;
      else 
        sda_stuck_cnt <= {WIDTH{1'b0}};
    end 
    assign sda_error = (sda_stuck_cnt >= sda_stuck_timeout);
    
    reg [CNT_WIDTH-1:0] t_sda_su, t_sda_hd, t_low, t_high,t_sto_su,
    t_buf,t_recovery_half_cycle;
    
    always @(*) begin 
      case (mode) 
        2'b00:begin //standard speed 
          t_sda_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STA_SU_STD);
          t_sda_hd = `ns_to_cyc(CLK_FREQ_MHZ, `T_STA_HD_STD);
          t_low = `ns_to_cyc(CLK_FREQ_MHZ, `T_LOW_STD);
          t_high = `ns_to_cyc(CLK_FREQ_MHZ, `T_HIGH_STD);
          t_sto_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STO_SU_STD);
          t_buf = `ns_to_cyc(CLK_FREQ_MHZ, `T_BUF_STD);
          t_recovery_half_cycle = `ns_to_cyc(CLK_FREQ_MHZ, `T_RECOVERY_HALF_CYCLE_STD);
        end 
        
        2'b01:begin 
          t_sda_su= `ns_to_cyc(CLK_FREQ_MHZ,`T_STA_SU_STD);
          t_sda_hd = `ns_to_cyc(CLK_FREQ_MHZ, `T_STA_HD_FAST);
          t_low = `ns_to_cyc(CLK_FREQ_MHZ, `T_LOW_FAST);
          t_high = `ns_to_cyc(CLK_FREQ_MHZ, `T_HIGH_FAST);
          t_sto_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STO_SU_FAST);
          t_buf = `ns_to_cyc(CLK_FREQ_MHZ, `T_BUF_FAST);
          t_recovery_half_cycle = `ns_to_cyc(CLK_FREQ_MHZ, `T_RECOVERY_HALF_CYCLE_FAST);
        end 
        
        2'b10: begin
          t_sda_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STA_SU_FASTP);
          t_sda_hd = `ns_to_cyc(CLK_FREQ_MHZ, `T_STA_HD_FASTP);
          t_low = `ns_to_cyc(CLK_FREQ_MHZ, `T_LOW_FASTP);
          t_high = `ns_to_cyc(CLK_FREQ_MHZ, `T_HIGH_FASTP);
          t_sto_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STO_SU_FASTP);
          t_buf = `ns_to_cyc(CLK_FREQ_MHZ, `T_BUF_FASTP);
          t_recovery_half_cycle = `ns_to_cyc(CLK_FREQ_MHZ, `T_RECOVERY_HALF_CYCLE_FASTP);
        end
        
        default: begin
          t_sda_su = `ns_to_cyc(CLK_FREQ_MHZ,`T_STA_SU_FAST);
          t_sda_hd = `ns_to_cyc(CLK_FREQ_MHZ,`T_STA_HD_FAST);
          t_low = `ns_to_cyc(CLK_FREQ_MHZ,`T_LOW_FASTP);
          t_high = `ns_to_cyc(CLK_FREQ_MHZ,`T_HIGH_FAST);
          t_sto_su = `ns_to_cyc(CLK_FREQ_MHZ, `T_STO_SU_FAST);
          t_buf = `ns_to_cyc(CLK_FREQ_MHZ, `T_BUF_FAST);
          t_recovery_half_cycle = `ns_to_cyc(CLK_FREQ_MHZ, `T_RECOVERY_HALF_CYCLE_FAST);
        end
      endcase      
    end 
    
    //detecting start and stop 
    
    wire start_sig ;
    wire stop_sig ;
    
    reg sda_1;
    always @(posedge clk or negedge rst_n) begin 
      if (!rst_n) sda_1 <= 1'b1;
      else sda_1 <= sda_syn;
    end 
    
    assign start_sig = sda_1 && !sda_syn && scl_syn ;
    assign stop_sig = !sda_1 && sda_syn && scl_syn ;
    
    //error recovery 
    
   
    reg [1:0] sda_intent;
    reg [4:0] recovery_count, next_recovery_count;
    
    always @(posedge clk or negedge rst_n) begin 
      if (!rst_n) 
        sda_intent <= 2'b11;
      else 
        sda_intent <= {!sda_oe , sda_intent[1]};
    end 
    
    reg [2:0] resp_state ;
    
    always @(posedge clk or negedge rst_n) begin 
      if (!rst_n) begin 
        resp_state <= RESP_IDLE;
        recovery_count <= 5'b0;
      end 
      else begin 
        resp_state <= resp ;
        recovery_count <= (recovery_count>18) ? 5'b0: next_recovery_count;
      end 
    end 
    
        always @(*) begin
        case(resp_state)
            RESP_IDLE, RESP_INPROGRESS, RESP_BUS_BUSY: begin
                if(scl_error) 
                    resp = RESP_SCL_ERR;
                else if(sda_error)
                    resp = RESP_SDA_RECOVERY;
                else begin
                    if(sda_intent[0] && !sda_syn && 
                        (state==START_SU || state==STOP_HOLD || state==TX_HIGH) && 1'b0)
                        resp = RESP_ARB_LOST;
                    else
                        resp = running ? RESP_INPROGRESS : ((state==BUS_BUSY) ? RESP_BUS_BUSY : RESP_IDLE);
                end
            end
            RESP_ARB_LOST: begin
                resp = (state==BUS_BUSY) ? RESP_ARB_LOST : RESP_IDLE;
            end
            RESP_SDA_RECOVERY: begin
                resp = (recovery_count>18) ? (sda_syn ? RESP_IDLE : RESP_SDA_ERR) : RESP_SDA_RECOVERY;  
            end
            RESP_SDA_ERR: begin
                resp = sda_syn ? RESP_IDLE : RESP_SDA_ERR;
            end
            RESP_SCL_ERR: begin
                resp = scl_syn ? RESP_IDLE : RESP_SCL_ERR;
            end
            default: begin
                resp = RESP_IDLE;
            end
        endcase
    end

   
  // localparam [WIDTH-1:0] C_BUF = ns_to_cyc(CLK_FREQ_MHZ,TBUF_NS);

//bit level fsm 

  reg scl_oe_next , sda_oe_next;
  reg ack,next_ack;
  
  reg [2:0]bit_idx, next_bit_idx;
  
  always @(posedge clk or negedge rst_n)
  begin 
    if (!rst_n) begin 
      bit_idx <= 3'b0;
      ack <= 1'b0;
      state <= IDLE;
      {sda_oe , scl_oe} <= 2'b00;
    end 
    else begin 
      bit_idx <= next_bit_idx;
      ack <= next_ack ;
      state <= next_state ;
      { sda_oe , scl_oe } <= {sda_oe_next, scl_oe_next};
    end 
  end 
  
  always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) 
      rx_data <= 8'b0;
    else if (state == RX_HIGH) 
      rx_data[bit_idx] <= count_done ? sda_syn : rx_data[bit_idx];
  end 
  
  always @(*) begin 
    count_value = {CNT_WIDTH{1'b0}};
    count_en =1'b0;
  
    next_recovery_count = 5'b0;
    next_bit_idx = bit_idx;
    next_ack = ack ;
    running = 1'b0;
    next_state = state ;
    {sda_oe_next, scl_oe_next} = {sda_oe , scl_oe};
    
    if(sda_error && state != SDA_RECOVERY) begin 
      next_state = SDA_RECOVERY;
    end 
    
    else 
    begin 
      //next_state = state ;
      case(state) 
        IDLE : begin 
          running = 1'b0 ;
          count_en = 1'b0;
          count_value = {CNT_WIDTH {1'b0}};
          next_bit_idx = 3'd7;
          next_ack = 1'b0;
          
          if (start_sig) begin 
            next_state = BUS_BUSY;
          end 
          else begin 
            case (trig ) 
              3'b001: next_state = START_SU;
              3'b010: next_state = TX_LOW;
              3'b011: next_state = RX_LOW;
              3'b100: next_state = STOP_LOW;
              default : next_state = IDLE ;
              
            endcase 
          end 
        end 
        
         BUS_BUSY :begin 
            running = 1'b0;
            next_state = stop_sig ?BUS_BUFF : BUS_BUSY;
            {sda_oe_next,scl_oe_next} = 2'b00;
          end 
          
         BUS_BUFF : begin 
          running = 1'b1;
          count_en = count_done ? 1'b0:1'b1;
          count_value = t_buf;
          next_state = count_done  ? IDLE : BUS_BUFF;
          {sda_oe_next, scl_oe_next} = 2'b00;
         end 
         
         START_SU :begin 
          running = 1'b1;
          count_en = count_done ? 1'b0:scl_syn;
          count_value = t_sda_su;
          next_state = count_done ?START_HOLD: START_SU;
          {sda_oe_next,scl_oe_next} = 2'b00;
         end 
         
         START_HOLD : begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: scl_syn;
          count_value = t_sda_hd;
          next_state = count_done ? IDLE : START_HOLD;
          {sda_oe_next, scl_oe_next}= 2'b10;
         end 
         
         TX_LOW :begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: 1'b1;
          count_value = t_low;
          next_state = count_done ? TX_HIGH : TX_LOW;
          {sda_oe_next, scl_oe_next} = {!tx_data[bit_idx],1'b1};
         end 
         
         TX_HIGH :begin 
          running = 1'b1;
          count_en = count_done? 1'b0: scl_syn;
          count_value = t_high;
          {sda_oe_next, scl_oe_next} = {!tx_data[bit_idx],1'b0};
          
          if (count_done) begin 
            if (ack) begin 
              next_state =IDLE;
            end 
            else begin 
              next_bit_idx= (bit_idx ==0) ? 3'd7: bit_idx -1'b1;
              next_state = (bit_idx == 3'd0) ? RX_LOW:TX_LOW;
              next_ack = (bit_idx == 3'd0);
            end 
          end 
          //{sda_oe_next, scl_oe_next} = { 1'b0, !tx_data[bit_idx]};
         end 
         
         RX_LOW:begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: 1'b1;
          count_value = t_low ;
          next_state = count_done ? RX_HIGH : RX_LOW;
          {sda_oe_next, scl_oe_next} = 2'b01;
         end 
         
         RX_HIGH: begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: scl_syn;
          count_value = t_high;
          {sda_oe_next,scl_oe_next} = 2'b00;
          if (count_done) begin 
            if (ack) begin 
              next_state = IDLE ;
            end 
            else begin 
              next_bit_idx=(bit_idx ==0) ? 3'd7: bit_idx-1'b1;
              next_state = (bit_idx == 3'd0) ? TX_LOW : RX_LOW;
              next_ack = (bit_idx == 3'd0);
            end
          end
         end 
         
         STOP_LOW: begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: 1'b1;
          count_value = t_low ;
          next_state = count_done ? STOP_SU:STOP_LOW;
          {sda_oe_next, sda_oe_next} = 2'b11;
         end 
         
         STOP_SU : begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: 1'b1;
          count_value = t_sto_su;
          next_state = count_done ? STOP_HOLD: STOP_SU;
          {sda_oe_next, scl_oe_next}= 2'b10;
         end 
         
         STOP_HOLD: begin 
          running = 1'b1;
          count_en = count_done ? 1'b0: 1'b1;
          count_value = t_buf;
          next_state = count_done ? IDLE : STOP_HOLD;
          {sda_oe_next, scl_oe_next} = 2'b00;
          
         end 
         
         SDA_RECOVERY: begin
          running = 1'b0;
          count_en = 1'b1;
          count_value = t_recovery_half_cycle ; 
          next_recovery_count = count_done ? recovery_count+1'b1 : recovery_count;
          next_state = (recovery_count>18) ? IDLE : SDA_RECOVERY;
          {scl_oe_next, sda_oe_next} = (count_done && recovery_count<18) ? {~scl_oe, 1'b0} : {scl_oe, 1'b0};

         end 
         
         default : begin 
          next_state= IDLE;
          running = 1'b0;
         end 
         
      endcase
    end 
  end
  
endmodule 
