cale 1ns/1ps
module i2c_glitch #(
    parameter FILTER_LEN = 3,
    parameter RESET_VAL  = 1'b1
) (
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    input  wire din,
    output wire dout
);

    localparam CW = (FILTER_LEN > 1) ? $clog2(FILTER_LEN) : 1;
    localparam [CW-1:0] LAST = FILTER_LEN - 1;

    reg          filt;   // filtered value
    reg [CW-1:0] cnt;    // consecutive samples that disagree with `filt`

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filt <= RESET_VAL;
            cnt  <= {CW{1'b0}};
        end else if (din == filt) begin
            cnt  <= {CW{1'b0}};          // input agrees: restart the count
        end else if (cnt == LAST) begin
            filt <= din;                 // disagreed FILTER_LEN cycles in a row
            cnt  <= {CW{1'b0}};
        end else begin
            cnt  <= cnt + 1'b1;
        end
    end

    assign dout = en ? filt : din;

    // Elaboration-time parameter check (simulation only).
    //     // synthesis translate_off
    //         initial begin
    //                 if (FILTER_LEN < 1) begin
    //                             $display("ERROR: i2c_glitch FILTER_LEN
    //                             (%0d) must be >= 1", FILTER_LEN);
    //                                         $finish;
    //                                                 end
    //                                                     end
    //                                                         // synthesis
    //                                                         translate_on
    //
    //                                                         endmodule
    //
