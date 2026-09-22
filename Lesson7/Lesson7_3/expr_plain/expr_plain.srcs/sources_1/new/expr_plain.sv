`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/22/2026 07:22:59 PM
// Design Name:
// Module Name: expr_plain
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


module expr_plain
(
    input  logic          clk,
    input  logic          rst,
    input  logic  [15:0]  a,
    input  logic  [15:0]  b,
    input  logic  [7:0]   c,
    input  logic  [7:0]   d,
    input  logic  [7:0]   e,
    output logic  [31:0]  result
);

    // Register declarations for input signals
    logic [15:0] a_reg, b_reg;
    logic [7:0]  c_reg, d_reg, e_reg;

    // Sequential logic to register the inputs
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            a_reg <= 16'b0;
            b_reg <= 16'b0;
            c_reg <= 8'b0;
            d_reg <= 8'b0;
            e_reg <= 8'b0;
        end
        else
        begin
            a_reg <= a;
            b_reg <= b;
            c_reg <= c;
            d_reg <= d;
            e_reg <= e;
        end
    end

    // Sequential logic to compute the result based on registered inputs
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
            result <= 32'b0;
        else
            result <= ((c_reg + d_reg - e_reg) * a_reg) * b_reg;
    end

endmodule
