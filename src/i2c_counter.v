`timescale 1ns/1ps
module i2c_counter #(
    parameter CNT_WIDTH = 24
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,
    input  wire                 clear,
    input  wire [CNT_WIDTH-1:0] max_count,
    output reg  [CNT_WIDTH-1:0] count,
    output wire                 done
);

    assign done = (count >= max_count);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= {CNT_WIDTH{1'b0}};
        else if (clear)
            count <= {CNT_WIDTH{1'b0}};
        else if (en && !done)
            count <= count + {{(CNT_WIDTH-1){1'b0}}, 1'b1};
    end

endmodule

