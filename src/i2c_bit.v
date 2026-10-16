<<<<<<< HEAD
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
=======
module i2c_bit #(
    parameter CLK_FREQ_MHZ     = 100,
    parameter WIDTH            = 24,
    parameter FILTER_LEN       = 3,
    parameter GLITCH_FILTER_EN = 1
) (
    input  wire             clk,
    input  wire             rst_n,

    // command interface (from i2c_byte_fsm)
    input  wire [2:0]       trig,
    input  wire [7:0]       tx_data,
    input  wire [1:0]       mode,               // 00 std, 01 fast, 10 fast+, 11 std
    input  wire [WIDTH-1:0] stretch_timeout,
    input  wire [WIDTH-1:0] sda_stuck_timeout,
    output reg  [7:0]       rx_data,
    output reg  [2:0]       resp,

    // open-drain bus
    input  wire             scl_in,
    input  wire             sda_in,
    output reg              scl_oe,
    output reg              sda_oe
);

    // ------------------------------------------------------------------
    // Encodings (must match i2c_byte_fsm)
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Timing constants in ns (Std / Fast / Fast+)
    // ------------------------------------------------------------------
    localparam integer T_STA_SU_STD  = 4700, T_STA_SU_FAST  = 600,  T_STA_SU_FASTP  = 260;
    localparam integer T_STA_HD_STD  = 4000, T_STA_HD_FAST  = 600,  T_STA_HD_FASTP  = 260;
    localparam integer T_LOW_STD     = 6000, T_LOW_FAST     = 1500, T_LOW_FASTP     = 600;
    localparam integer T_HIGH_STD    = 4000, T_HIGH_FAST    = 1000, T_HIGH_FASTP    = 400;
    localparam integer T_STO_SU_STD  = 4000, T_STO_SU_FAST  = 600,  T_STO_SU_FASTP  = 260;
    localparam integer T_BUF_STD     = 4700, T_BUF_FAST     = 1300, T_BUF_FASTP     = 500;
    localparam integer T_HD_DAT = 300;      // SDA hold after SCL falls (all modes)
    localparam integer T_RECOVERY_HALF_CYCLE_STD  = 5000,
                       T_RECOVERY_HALF_CYCLE_FAST = 1250,
                       T_RECOVERY_HALF_CYCLE_FASTP = 500;

    // ns -> clk cycles, rounded up (never shorter than the requested time)
`define NS2C(ns) (((CLK_FREQ_MHZ) * (ns) + 999) / 1000)

    // Counter width sized from the LARGEST constant (T_LOW_STD); checked below.
    localparam CNT_WIDTH = $clog2(`NS2C(T_LOW_STD) + 1);

    // ------------------------------------------------------------------
    // Input conditioning: sync_2ff -> i2c_glitch
    // ------------------------------------------------------------------
    wire scl_s, sda_s;      // synchronized
    wire scl_syn, sda_syn;  // synchronized + glitch-filtered
    wire gf_en = (GLITCH_FILTER_EN != 0) ? 1'b1 : 1'b0;

    sync_2ff s1 (.clk(clk), .rst_n(rst_n), .din(scl_in), .dout(scl_s));
    sync_2ff s2 (.clk(clk), .rst_n(rst_n), .din(sda_in), .dout(sda_s));

    i2c_glitch #(.FILTER_LEN(FILTER_LEN), .RESET_VAL(1'b1)) g1
        (.clk(clk), .rst_n(rst_n), .en(gf_en), .din(scl_s), .dout(scl_syn));
    i2c_glitch #(.FILTER_LEN(FILTER_LEN), .RESET_VAL(1'b1)) g2
        (.clk(clk), .rst_n(rst_n), .en(gf_en), .din(sda_s), .dout(sda_syn));

    wire bus_free = scl_syn & sda_syn;

    // ------------------------------------------------------------------
    // Speed-mode timing in clk cycles
    // ------------------------------------------------------------------
    reg [CNT_WIDTH-1:0] t_sta_su, t_sta_hd, t_low, t_high, t_sto_su, t_buf, t_rec;
    localparam [CNT_WIDTH-1:0] ONE = 1;
    wire [CNT_WIDTH-1:0] t_hd    = `NS2C(T_HD_DAT);   // SDA hold cycles (>= 1)
    wire [CNT_WIDTH-1:0] t_hd_p1 = t_hd + ONE;

    always @* begin
        case (mode)
            2'b01: begin   // Fast
                t_sta_su = `NS2C(T_STA_SU_FAST);
                t_sta_hd = `NS2C(T_STA_HD_FAST);
                t_low    = `NS2C(T_LOW_FAST);
                t_high   = `NS2C(T_HIGH_FAST);
                t_sto_su = `NS2C(T_STO_SU_FAST);
                t_buf    = `NS2C(T_BUF_FAST);
                t_rec    = `NS2C(T_RECOVERY_HALF_CYCLE_FAST);
            end
            2'b10: begin   // Fast+
                t_sta_su = `NS2C(T_STA_SU_FASTP);
                t_sta_hd = `NS2C(T_STA_HD_FASTP);
                t_low    = `NS2C(T_LOW_FASTP);
                t_high   = `NS2C(T_HIGH_FASTP);
                t_sto_su = `NS2C(T_STO_SU_FASTP);
                t_buf    = `NS2C(T_BUF_FASTP);
                t_rec    = `NS2C(T_RECOVERY_HALF_CYCLE_FASTP);
            end
            default: begin // Standard (also mode 2'b11)
                t_sta_su = `NS2C(T_STA_SU_STD);
                t_sta_hd = `NS2C(T_STA_HD_STD);
                t_low    = `NS2C(T_LOW_STD);
                t_high   = `NS2C(T_HIGH_STD);
                t_sto_su = `NS2C(T_STO_SU_STD);
                t_buf    = `NS2C(T_BUF_STD);
                t_rec    = `NS2C(T_RECOVERY_HALF_CYCLE_STD);
            end
        endcase
    end

    // a - k, floored at 0
    function [CNT_WIDTH-1:0] sub_sat;
        input [CNT_WIDTH-1:0] a;
        input [CNT_WIDTH-1:0] k;
        begin
            sub_sat = (a > k) ? (a - k) : {CNT_WIDTH{1'b0}};
        end
    endfunction

    // ------------------------------------------------------------------
    // FSM state encoding
    // ------------------------------------------------------------------
    localparam [4:0] S_IDLE     = 5'd0,   // bus free, both lines released
                     S_HOLD     = 5'd1,   // bus owned, SCL low, waiting for a command
                     S_CHK      = 5'd2,   // START requested: is the bus free?
                     S_ST_REL   = 5'd3,   // release SDA (SCL low if repeated START)
                     S_ST_SCLH  = 5'd4,   // release SCL, wait high, START setup time
                     S_ST_SDAL  = 5'd5,   // pull SDA low, START hold time
                     S_ST_SCLL  = 5'd6,   // pull SCL low -> HOLD
                     S_BIT_SET  = 5'd7,   // SCL low, SDA unchanged (data hold)
                     S_BIT_LOW  = 5'd8,   // SCL low, SDA set to the bit value
                     S_BIT_HIGH = 5'd9,   // SCL released; wait high; sample SDA
                     S_SP_SDAL  = 5'd10,  // STOP: SDA low while SCL low
                     S_SP_SCLH  = 5'd11,  // STOP: release SCL, setup time
                     S_SP_SDAH  = 5'd12,  // STOP: release SDA, bus-free time
                     S_REC_LOW  = 5'd13,  // recovery clock: low half
                     S_REC_HIGH = 5'd14,  // recovery clock: high half
                     S_REC_END  = 5'd15,  // recovery: settle with SCL low
                     S_ABORT    = 5'd16;  // release both lines, report err_code

    reg [4:0] state, state_n;

    // ------------------------------------------------------------------
    // Datapath registers
    // ------------------------------------------------------------------
    reg [7:0] tx_buf,  tx_buf_n;
    reg [7:0] rx_buf,  rx_buf_n;
    reg [2:0] bit_idx, bit_idx_n;
    reg       ack_phase, ack_phase_n;   // currently on the 9th (ACK) bit
    reg       op_rx,     op_rx_n;       // 1 = RX command, 0 = TX command
    reg       ack_lat,   ack_lat_n;     // ACK bit to send after an RX byte
    reg       bus_owned, bus_owned_n;   // engine has issued START and no STOP yet
    reg       rec_mode,  rec_mode_n;    // STOP is the tail of a bus recovery
    reg [3:0] rec_cnt,   rec_cnt_n;     // recovery clock pulses completed
    reg [2:0] err_code,  err_code_n;    // result to report from S_ABORT

    reg [7:0] rx_data_n;
    reg [2:0] resp_n;
    reg       scl_oe_n, sda_oe_n;

    // SDA drive value during S_BIT_LOW
    wire bit_sda_oe = ack_phase ? (op_rx ? ~ack_lat : 1'b0)
                                : (op_rx ? 1'b0      : ~tx_buf[7]);

    // ------------------------------------------------------------------
    // Timing counter (i2c_counter, done = count >= max_count)
    //   * cleared whenever the state changes
    //   * in "waiting for SCL high" states it only counts while SCL is high
    // ------------------------------------------------------------------
    wire scl_wait_state = (state == S_ST_SCLH) || (state == S_BIT_HIGH) ||
                          (state == S_SP_SCLH) || (state == S_REC_HIGH);

    reg  [CNT_WIDTH-1:0] max_count;
    wire                 cnt_done;
    wire                 cnt_en    = scl_wait_state ? scl_syn : 1'b1;
    wire                 cnt_clear = (state_n != state);
    // In SCL-wait states the time only counts once SCL is really high.
    wire                 done_ok   = cnt_done & (~scl_wait_state | scl_syn);

    always @* begin
        case (state)
            S_ST_REL:                            max_count = bus_owned ? sub_sat(t_low, ONE)
                                                                       : {CNT_WIDTH{1'b0}};
            S_ST_SCLH:                           max_count = sub_sat(t_sta_su, ONE);
            S_ST_SDAL:                           max_count = sub_sat(t_sta_hd, ONE);
            S_HOLD:                              max_count = sub_sat(t_hd,     ONE);    // SCL-low -> START/STOP hold
            S_BIT_SET:                           max_count = sub_sat(t_hd,     ONE);    // SDA hold (T_HD_DAT)
            S_BIT_LOW:                           max_count = sub_sat(t_low,    t_hd_p1); // rest of tLOW
            S_BIT_HIGH:                          max_count = sub_sat(t_high,   ONE);
            S_SP_SDAL:                           max_count = sub_sat(t_low,    ONE);
            S_SP_SCLH:                           max_count = sub_sat(t_sto_su, ONE);
            S_SP_SDAH:                           max_count = sub_sat(t_buf,    ONE);
            S_REC_LOW, S_REC_HIGH, S_REC_END:    max_count = sub_sat(t_rec,    ONE);
            default:                             max_count = {CNT_WIDTH{1'b0}};
        endcase
    end

    i2c_counter #(.CNT_WIDTH(CNT_WIDTH)) u_cnt (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (cnt_en),
        .clear     (cnt_clear),
        .max_count (max_count),
        .count     (),
        .done      (cnt_done)
    );

    // ------------------------------------------------------------------
    // Timeout counters
    // ------------------------------------------------------------------
    reg [WIDTH-1:0] stretch_cnt;
    reg [WIDTH-1:0] sda_stuck_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stretch_cnt <= {WIDTH{1'b0}};
        else if (scl_wait_state && !scl_syn) begin
            if (stretch_cnt != {WIDTH{1'b1}})
                stretch_cnt <= stretch_cnt + 1'b1;
        end else
            stretch_cnt <= {WIDTH{1'b0}};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sda_stuck_cnt <= {WIDTH{1'b0}};
        else if (state == S_CHK && !bus_free) begin
            if (sda_stuck_cnt != {WIDTH{1'b1}})
                sda_stuck_cnt <= sda_stuck_cnt + 1'b1;
        end else
            sda_stuck_cnt <= {WIDTH{1'b0}};
    end

    wire stretch_to   = scl_wait_state && !scl_syn &&
                        (stretch_timeout != {WIDTH{1'b0}}) &&
                        (stretch_cnt >= stretch_timeout);
    wire sda_stuck_to = (sda_stuck_timeout != {WIDTH{1'b0}}) &&
                        (sda_stuck_cnt >= sda_stuck_timeout);

    // ------------------------------------------------------------------
    // Next-state / next-output logic
    // ------------------------------------------------------------------
    always @* begin
        // defaults: hold everything
        state_n     = state;
        resp_n      = resp;
        rx_data_n   = rx_data;
        tx_buf_n    = tx_buf;
        rx_buf_n    = rx_buf;
        bit_idx_n   = bit_idx;
        ack_phase_n = ack_phase;
        op_rx_n     = op_rx;
        ack_lat_n   = ack_lat;
        bus_owned_n = bus_owned;
        rec_mode_n  = rec_mode;
        rec_cnt_n   = rec_cnt;
        err_code_n  = err_code;
        scl_oe_n    = scl_oe;
        sda_oe_n    = sda_oe;

        // ---- line drive for the CURRENT state (registered -> lags 1 cycle) ----
        case (state)
            S_IDLE, S_CHK, S_ABORT: begin sda_oe_n = 1'b0; scl_oe_n = 1'b0; end
            S_HOLD, S_BIT_SET,
            S_ST_SCLL:              scl_oe_n = 1'b1;
            S_ST_REL:               sda_oe_n = 1'b0;
            S_ST_SCLH:              scl_oe_n = 1'b0;
            S_ST_SDAL:              sda_oe_n = 1'b1;
            S_BIT_LOW:              begin scl_oe_n = 1'b1; sda_oe_n = bit_sda_oe; end
            S_BIT_HIGH:             scl_oe_n = 1'b0;
            S_SP_SDAL:              begin sda_oe_n = 1'b1; scl_oe_n = 1'b1; end
            S_SP_SCLH:              scl_oe_n = 1'b0;
            S_SP_SDAH:              sda_oe_n = 1'b0;
            S_REC_LOW:              begin sda_oe_n = 1'b0; scl_oe_n = 1'b1; end
            S_REC_HIGH:             begin sda_oe_n = 1'b0; scl_oe_n = 1'b0; end
            S_REC_END:              begin sda_oe_n = 1'b0; scl_oe_n = 1'b1; end
            default: ;
        endcase

        // ---- state transitions ----
        case (state)
            // ------------------------------------------------ IDLE
            S_IDLE: begin
                case (trig)
                    TRIG_START: begin
                        resp_n  = RESP_INPROGRESS;
                        state_n = S_CHK;
                    end
                    TRIG_TX, TRIG_RX: begin        // not allowed without a START
                        resp_n     = RESP_INPROGRESS;
                        err_code_n = RESP_BUS_BUSY;
                        state_n    = S_ABORT;
                    end
                    TRIG_STOP: begin               // nothing to stop
                        resp_n     = RESP_INPROGRESS;
                        err_code_n = RESP_IDLE;
                        state_n    = S_ABORT;
                    end
                    default: ;
                endcase
            end

            // ------------------------------------------------ HOLD
            S_HOLD: begin
                // TX/RX need no extra wait here (S_BIT_SET supplies the SDA hold).
                // START/STOP move SDA right away, so they wait until SCL has been
                // low for T_HD_DAT (counter in S_HOLD, done_ok).
                case (trig)
                    TRIG_START: if (done_ok) begin
                        resp_n  = RESP_INPROGRESS;
                        state_n = S_ST_REL;
                    end
                    TRIG_TX: begin
                        resp_n      = RESP_INPROGRESS;
                        tx_buf_n    = tx_data;
                        op_rx_n     = 1'b0;
                        bit_idx_n   = 3'd7;
                        ack_phase_n = 1'b0;
                        state_n     = S_BIT_SET;
                    end
                    TRIG_RX: begin
                        resp_n      = RESP_INPROGRESS;
                        rx_buf_n    = 8'h00;
                        op_rx_n     = 1'b1;
                        ack_lat_n   = tx_data[0];   // 0 = ACK, 1 = NACK
                        bit_idx_n   = 3'd7;
                        ack_phase_n = 1'b0;
                        state_n     = S_BIT_SET;
                    end
                    TRIG_STOP: if (done_ok) begin
                        resp_n     = RESP_INPROGRESS;
                        rec_mode_n = 1'b0;
                        state_n    = S_SP_SDAL;
                    end
                    default: ;
                endcase
            end

            // ------------------------------------------------ START
            S_CHK: begin
                if (bus_free) begin
                    state_n = S_ST_REL;
                end else if (sda_stuck_timeout == {WIDTH{1'b0}}) begin
                    err_code_n = RESP_BUS_BUSY;
                    state_n    = S_ABORT;
                end else if (sda_stuck_to) begin
                    if (scl_syn) begin             // SDA stuck low, SCL free -> recover
                        rec_mode_n = 1'b1;
                        rec_cnt_n  = 4'd0;
                        state_n    = S_REC_LOW;
                    end else begin                 // SCL held low
                        err_code_n = RESP_SCL_ERR;
                        state_n    = S_ABORT;
                    end
                end
            end

            S_ST_REL: begin
                if (done_ok) state_n = S_ST_SCLH;
            end

            S_ST_SCLH: begin
                if (stretch_to) begin
                    err_code_n = RESP_SCL_ERR;
                    state_n    = S_ABORT;
                end else if (done_ok) begin
                    if (sda_syn) begin
                        state_n = S_ST_SDAL;
                    end else begin
                        err_code_n = bus_owned ? RESP_ARB_LOST : RESP_BUS_BUSY;
                        state_n    = S_ABORT;
                    end
                end
            end

            S_ST_SDAL: begin
                if (done_ok) state_n = S_ST_SCLL;
            end

            S_ST_SCLL: begin
                bus_owned_n = 1'b1;
                resp_n      = RESP_IDLE;
                state_n     = S_HOLD;
            end

            // ------------------------------------------------ BIT CELL
            S_BIT_SET: begin                       // SDA hold (T_HD_DAT) with SCL low
                if (done_ok) state_n = S_BIT_LOW;
            end

            S_BIT_LOW: begin
                if (done_ok) state_n = S_BIT_HIGH;
            end

            S_BIT_HIGH: begin
                if (stretch_to) begin
                    err_code_n = RESP_SCL_ERR;
                    state_n    = S_ABORT;
                end else if (done_ok) begin
                    if (!ack_phase) begin
                        if (!op_rx && tx_buf[7] && !sda_syn) begin
                            // we released SDA (sent 1) but it reads 0: lost arbitration
                            err_code_n = RESP_ARB_LOST;
                            state_n    = S_ABORT;
                        end else begin
                            if (op_rx) rx_buf_n = {rx_buf[6:0], sda_syn};
                            else       tx_buf_n = {tx_buf[6:0], 1'b0};
                            if (bit_idx == 3'd0) ack_phase_n = 1'b1;
                            else                 bit_idx_n   = bit_idx - 3'd1;
                            state_n = S_BIT_SET;
                        end
                    end else begin
                        // ACK bit finished
                        rx_data_n = op_rx ? rx_buf : {7'b0, sda_syn};
                        resp_n    = RESP_IDLE;
                        state_n   = S_HOLD;
                    end
                end
            end

            // ------------------------------------------------ STOP
            S_SP_SDAL: begin
                if (done_ok) state_n = S_SP_SCLH;
            end

            S_SP_SCLH: begin
                if (stretch_to) begin
                    err_code_n = RESP_SCL_ERR;
                    state_n    = S_ABORT;
                end else if (done_ok) begin
                    state_n = S_SP_SDAH;
                end
            end

            S_SP_SDAH: begin
                if (done_ok) begin
                    bus_owned_n = 1'b0;
                    rec_mode_n  = 1'b0;
                    state_n     = S_IDLE;
                    if (rec_mode) resp_n = sda_syn ? RESP_SDA_RECOVERY : RESP_SDA_ERR;
                    else          resp_n = RESP_IDLE;
                end
            end

            // ------------------------------------------------ BUS RECOVERY
            S_REC_LOW: begin
                if (done_ok) state_n = S_REC_HIGH;
            end

            S_REC_HIGH: begin
                if (stretch_to) begin
                    err_code_n = RESP_SCL_ERR;
                    state_n    = S_ABORT;
                end else if (done_ok) begin
                    if (rec_cnt == 4'd8) begin     // 9th pulse done
                        state_n = S_REC_END;
                    end else begin
                        rec_cnt_n = rec_cnt + 4'd1;
                        state_n   = S_REC_LOW;
                    end
                end
            end

            S_REC_END: begin
                if (done_ok) state_n = S_SP_SDAL;  // then a normal STOP (rec_mode = 1)
            end

            // ------------------------------------------------ ABORT
            S_ABORT: begin
                bus_owned_n = 1'b0;
                rec_mode_n  = 1'b0;
                resp_n      = err_code;
                state_n     = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
>>>>>>> updated hopefully
            end
        endcase
    end

<<<<<<< HEAD
   
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
=======
    // ------------------------------------------------------------------
    // State / register update
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            resp      <= RESP_IDLE;
            rx_data   <= 8'h00;
            tx_buf    <= 8'h00;
            rx_buf    <= 8'h00;
            bit_idx   <= 3'd7;
            ack_phase <= 1'b0;
            op_rx     <= 1'b0;
            ack_lat   <= 1'b0;
            bus_owned <= 1'b0;
            rec_mode  <= 1'b0;
            rec_cnt   <= 4'd0;
            err_code  <= RESP_IDLE;
            scl_oe    <= 1'b0;
            sda_oe    <= 1'b0;
        end else begin
            state     <= state_n;
            resp      <= resp_n;
            rx_data   <= rx_data_n;
            tx_buf    <= tx_buf_n;
            rx_buf    <= rx_buf_n;
            bit_idx   <= bit_idx_n;
            ack_phase <= ack_phase_n;
            op_rx     <= op_rx_n;
            ack_lat   <= ack_lat_n;
            bus_owned <= bus_owned_n;
            rec_mode  <= rec_mode_n;
            rec_cnt   <= rec_cnt_n;
            err_code  <= err_code_n;
            scl_oe    <= scl_oe_n;
            sda_oe    <= sda_oe_n;
        end
    end

endmodule

>>>>>>> updated hopefully
