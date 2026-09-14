`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/14/2026 11:25:54 PM
// Design Name:
// Module Name: counter
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

/*-----------------------------------------------------------------------
                                Task 1
-----------------------------------------------------------------------*/
module counter
(
    // Inputs
    input logic clk,
    input logic rst,
    input logic load,
    input logic [3:0] data_in,
    input logic en,
    input logic up_down,
    // Outputs
    output logic [3:0] count
);

    // Counter logic
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
            count <= 4'b0000;
        else if (load)
            count <= data_in;
        else if (en)
            if (up_down)
                count <= count + 4'd1;
            else
                count <= count - 4'd1;
        else
            count <= count;
    end
endmodule
