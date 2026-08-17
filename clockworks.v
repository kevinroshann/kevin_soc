module Slow #(
    parameter SLOW = 21
)(
    input clk,
    input resetn,
    output CLK,
    output RESETN
);

    reg [SLOW:0] counter=0;

    always @(posedge clk) begin
        counter<=counter+1;
    end

    assign CLK=counter[SLOW];
    assign RESETN=1'b1;


endmodule