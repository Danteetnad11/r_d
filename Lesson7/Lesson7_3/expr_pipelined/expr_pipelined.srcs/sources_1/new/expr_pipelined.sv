`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/22/2026 10:20:31 PM
// Design Name:
// Module Name: expr_pipelined
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


module expr_pipelined
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

    // Register declaration for intermediate results of the pipeline stages
    logic [7:0] partial_result_1;
    logic [31:0] partial_result_2;

    // Sequential logic to compute the intermediate results of the pipeline stages
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            partial_result_1 <= 8'b0;
            partial_result_2 <= 32'b0;
        end
        else
        begin
            partial_result_1 <= (c_reg + d_reg - e_reg);
            partial_result_2 <= a_reg * b_reg;
        end
    end

    // Sequential logic to compute the final result based on intermediate results
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
            result <= 32'b0;
        else
            result <= (partial_result_1 * partial_result_2);
    end

endmodule
