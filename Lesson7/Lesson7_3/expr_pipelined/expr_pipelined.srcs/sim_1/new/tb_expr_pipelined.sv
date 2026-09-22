`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/22/2026 10:30:06 PM
// Design Name:
// Module Name: tb_expr_pipelined
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


module tb_expr_pipelined;
    // Testbench signals
    logic          clk;
    logic          rst;
    logic  [15:0]  a;
    logic  [15:0]  b;
    logic  [7:0]   c;
    logic  [7:0]   d;
    logic  [7:0]   e;
    logic  [31:0]  result;

    // Instantiate the DUT
    expr_pipelined dut
    (
        .clk    (clk),
        .rst    (rst),
        .a      (a),
        .b      (b),
        .c      (c),
        .d      (d),
        .e      (e),
        .result (result)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check_expr
    (
        input logic  [15:0]  a_val,
        input logic  [15:0]  b_val,
        input logic  [7:0]   c_val,
        input logic  [7:0]   d_val,
        input logic  [7:0]   e_val,
        input logic  [31:0]  expected_result,
        input string  test_name
    );
        a = a_val;
        b = b_val;
        c = c_val;
        d = d_val;
        e = e_val;
        @(posedge clk); #1; // Wait for a delta cycle to allow the DUT to process the inputs
        @(posedge clk); #1; // Wait for another clock edge to capture the intermediate results
        @(posedge clk); #1; // Wait for the final result after the pipeline stages

        if (result !== expected_result)
            $display("[%0t ns] Test %s failed: expected %h, got %h", $time, test_name, expected_result, result);
        else
            $display("[%0t ns] Test %s passed", $time, test_name);
    endtask

    // Test stimulus
    initial
    begin
        // Apply reset
        rst = 1;
        a = 16'h0;
        b = 16'h0;
        c = 8'h0;
        d = 8'h0;
        e = 8'h0;

        @(posedge clk); #1;
        rst = 0;

        check_expr(16'h4, 16'h5, 8'h2, 8'h2, 8'h3, 32'h00000014, "(2+2-3)*4*5 = 20");
        check_expr(16'h8, 16'h9, 8'h5, 8'h6, 8'h7, 32'h00000120, "(5+6-7)*8*9 = 288");
        #100;
        $finish;
    end
endmodule
