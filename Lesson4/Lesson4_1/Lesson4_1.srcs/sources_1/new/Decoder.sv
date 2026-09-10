`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/09/2026 06:39:38 PM
// Design Name:
// Module Name: Decoder
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

`define CALCULATE_INPUT_WIDTH(WIDTH) ($clog2(WIDTH))

module Decoder #(parameter WIDTH = 4)
(
    input  logic [`CALCULATE_INPUT_WIDTH(WIDTH)-1:0] decoderIn,
    output logic [WIDTH-1:0] decoderOut
);

    assign decoderOut = 1'b1 << decoderIn;

endmodule
