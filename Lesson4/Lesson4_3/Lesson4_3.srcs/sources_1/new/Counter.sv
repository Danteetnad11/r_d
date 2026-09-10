`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/10/2026 04:42:52 PM
// Design Name:
// Module Name: Counter
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module Counter
(
    input logic clock,
    input logic reset,
    output logic [3:0] led
);

    always_ff @(posedge clock or posedge reset)
    begin
        if (reset)
            led <= 4'b0000;
        else
            led <= led + 1;
    end

endmodule
