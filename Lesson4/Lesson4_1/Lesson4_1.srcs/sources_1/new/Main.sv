`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/09/2026 06:39:38 PM
// Design Name:
// Module Name: main
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

module Main
(
    input  logic [1:0] in4,
    output logic [3:0] out4,
    input  logic [2:0] in8,
    output logic [7:0] out8
);
    Decoder #(4) decoder_inst4
    (
        .decoderIn(in4),
        .decoderOut(out4)
    );

    Decoder #(8) decoder_inst8
    (
        .decoderIn(in8),
        .decoderOut(out8)
    );
endmodule
