`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/10/2026 03:51:19 PM
// Design Name:
// Module Name: Mux
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


module Mux
(
    input logic select,
    input logic input_0,
    input logic input_1,
    output logic output_y
);

    always_comb
    begin
        if (select)
            output_y = input_1;
        else
            output_y = input_0;
    end

endmodule
