//i2c_fifo

`timescale 1ns / 1ps


module i2c_fifo #(parameter DEPTH =1024, parameter WIDTH=8 
)(
  input wire clk, 
  input wire rst_n,
  input wire w_en, 
  input wire r_en,
  input [WIDTH-1:0] data_in,
  output reg [WIDTH-1:0] data_out,
  output wire full , 
  output wire empty,
  output reg overflow,
  output reg underflow,
  output wire [$clog2(DEPTH) :0] count 
    );
    
     localparam  ADDR_WIDTH = $clog2(DEPTH);

    //wirte pointer and read pointer 
    reg [ADDR_WIDTH :0] w_ptr, r_ptr;
    //memory 
    reg [WIDTH-1:0] fifo [DEPTH-1:0];
    wire [ADDR_WIDTH-1:0] w_addr = w_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] r_addr = r_ptr[ADDR_WIDTH-1:0];
    
    assign full = ((w_ptr[ADDR_WIDTH-1:0]) == r_ptr[ADDR_WIDTH-1:0])&&(w_ptr [ADDR_WIDTH] != r_ptr[ADDR_WIDTH]);
    assign empty =(w_ptr == r_ptr);
    assign count = w_ptr - r_ptr;
    
    
    always @(posedge clk or negedge rst_n ) begin 
      if (!rst_n) begin 
        w_ptr <= 0;
        r_ptr <= 0;
        data_out <= 0 ; 
        overflow <= 0 ;
        underflow <= 0 ;
      end 
      else begin 
        overflow <= w_en && full ;
        underflow <= r_en && empty;
        
        if (w_en && !full) begin 
          fifo[w_addr] <= data_in;
          w_ptr <= w_ptr +1'b1;
        end 
        
        else if (r_en && !empty) begin 
          data_out <= fifo[r_addr];
          r_ptr <= r_ptr + 1'b1;
        end 
      end 
      
    end 
    

endmodule

