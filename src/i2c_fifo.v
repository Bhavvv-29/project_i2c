`timescale 1ns/1ps
module i2c_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 1024
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     w_en,
    input  wire [WIDTH-1:0]         w_data,

    input  wire                     r_en,
    output wire [WIDTH-1:0]         r_data,

    output wire                     full,
    output wire                     empty,
    output wire [$clog2(DEPTH):0]   count,

    output reg                      overflow,
    output reg                      underflow
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // One extra pointer bit distinguishes full from empty.
    reg [ADDR_WIDTH:0]  wptr;
    reg [ADDR_WIDTH:0]  rptr;
    reg [WIDTH-1:0]     mem [0:DEPTH-1];

    assign count = wptr - rptr;
    assign empty = (wptr == rptr);
    assign full  = count[ADDR_WIDTH];          // count == DEPTH

    wire do_write = w_en && !full;
    wire do_read  = r_en && !empty;

    assign r_data = empty ? {WIDTH{1'b0}} : mem[rptr[ADDR_WIDTH-1:0]];

    always @(posedge clk) begin
        if (do_write)
            mem[wptr[ADDR_WIDTH-1:0]] <= w_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr      <= {(ADDR_WIDTH+1){1'b0}};
            rptr      <= {(ADDR_WIDTH+1){1'b0}};
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            if (do_write) wptr <= wptr + 1'b1;
            if (do_read)  rptr <= rptr + 1'b1;
            overflow  <= w_en && full;
            underflow <= r_en && empty;
        end
    end

endmodule

