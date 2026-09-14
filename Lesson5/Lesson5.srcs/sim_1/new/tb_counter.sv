`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/14/2026 11:28:02 PM
// Design Name:
// Module Name: tb_counter
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
                                Task 2
Initialize all signals to default values and instantiate the counter module.
-----------------------------------------------------------------------*/
module tb_counter;

    // Signals driving the counter inputs
    logic clk;
    logic rst;
    logic load;
    logic [3:0] data_in;
    logic en;
    logic up_down;

    // Counter output
    logic [3:0] count;

    // Instantiate the counter module
    counter uut
    (
        .clk(clk),
        .rst(rst),
        .load(load),
        .data_in(data_in),
        .en(en),
        .up_down(up_down),
        .count(count)
    );

    // Clock generation
    initial clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz clock

/*-----------------------------------------------------------------------
                                Task 3
Check LOAD functionality
-----------------------------------------------------------------------*/
// Check Load functionality

    initial
    begin
        // Initialize signals
        en = 1'b0;
        $display("[%0t ns]: Before reset count = %b", $time, count); // Initial value of the counter before reset should be X

        rst = 1'b1;
        load = 1'b0;
        data_in = 4'd0;

        up_down = 1'b1;

        // Hold reset through one rising clock edge.
        @(posedge clk);
        #1;
        rst = 1'b0;

        // Load 10 and wait for the nonblocking assignment to complete.
        load = 1'b1;
        data_in = 4'd10;
        @(posedge clk);
        #1;
        load = 1'b0;

        check_count(4'd10, "LOAD");

/*-----------------------------------------------------------------------
                                Task 4
Check COUNT UP functionality with wraparound case
-----------------------------------------------------------------------*/
        // Continue from 10: enable counting up.
        en = 1'b1;
        up_down = 1'b1;

        //Wait for 3 clock cycles: 10 -> 11 -> 12 -> 13
        repeat (3)
        begin
            @(posedge clk);
            #1;
        end

        check_count(4'd13, "COUNT UP");

        // Three more cycles: 13 -> 14 -> 15 -> 0.
        repeat (3)
        begin
            @(posedge clk);
            #1;
        end

        check_count(4'd0, "WRAPAROUND");

/*-----------------------------------------------------------------------
                                Task 5
Check ENABLE functionality
-----------------------------------------------------------------------*/
        // Disable counting to check that the counter holds its value.
        en = 1'b0;

        // Wait for 2 clock cycles to verify that the counter does not change.
        repeat (2)
        begin
            @(posedge clk);
            #1;
        end

        check_count(4'd0, "ENABLE");

/*-----------------------------------------------------------------------
                                Task 6
Check COUNT DOWN functionality with wraparound case
-----------------------------------------------------------------------*/
        //Enable counting and set it to count down.
        en = 1'b1;
        up_down = 1'b0;

        @(posedge clk);
        #1;

        check_count(4'd15, "COUNT DOWN");

/*-----------------------------------------------------------------------
                                Task 7
Check LOAD over ENABLE priority
-----------------------------------------------------------------------*/
        // Load a value into the counter while enable is high to check priority.
        en = 1'b1;
        up_down = 1'b1;
        load = 1'b1;
        data_in = 4'd5;

        @(posedge clk);
        #1;

        check_count(4'd5, "LOAD priority");

/*-----------------------------------------------------------------------
                                Bonus task
Check COUNT DOWN without wraparound: 8 -> 7
-----------------------------------------------------------------------*/
        en = 1'b0;
        load = 1'b1;
        data_in = 4'd8;
        up_down = 1'b0;

        @(posedge clk);
        #1;
        check_count(4'd8, "BONUS LOAD 8");

        load = 1'b0;
        en = 1'b1;

        @(posedge clk);
        #1;
        check_count(4'd7, "BONUS COUNT DOWN");

        $finish;
    end

/*-----------------------------------------------------------------------
                                Task 8
Implement a task to check the counter value.
-----------------------------------------------------------------------*/
        task automatic check_count(input [3:0] expected_count, input string task_name);
            if (count === expected_count)
                $display("[%0t ns]: PASS: %s, count = %0d (expected %0d)", $time, task_name, count, expected_count);
            else
                $display("[%0t ns]: FAIL: %s, count = %0d (expected %0d)", $time, task_name, count, expected_count);
        endtask
endmodule

/*-----------------------------------------------------------------------
                                Task 9
Find the X state of the counter before reset
-----------------------------------------------------------------------*/
// До reset значення count є X, оскільки регістр ще не отримав визначеного початкового значення (Див. Task10_Console_output.png).