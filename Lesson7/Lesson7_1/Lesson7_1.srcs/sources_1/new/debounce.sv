`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/16/2026 04:50:28 PM
// Design Name:
// Module Name: debounce
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


module debounce #(
    // Consecutive stable samples required, after synchronization; minimum 1.
    parameter int unsigned DEBOUNCE_CYCLES = 1_000_000
)
(
    input logic clk, // Clock signal
    input logic rst, // Asynchronous reset signal, active high
    input logic [3:0] digit_in, // Raw button input
    output logic [3:0] digit_filtered, // Debounced output
    output logic digit_valid // One-clock pulse for an accepted stable digit change, including zero.
);
    localparam int COUNT_WIDTH = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES + 1);

    // Synchronize the asynchronous button bus before testing its stability.
    // All four bits must then remain unchanged for the debounce interval.
    (* ASYNC_REG = "TRUE" *) logic [3:0] digit_presync, digit_sync;
    logic [3:0] candidate_digit;
    logic [COUNT_WIDTH-1:0] stable_count;

    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            digit_presync <= 4'd0;
            digit_sync <= 4'd0;
        end
        else
        begin
            digit_presync <= digit_in;
            digit_sync <= digit_presync;
        end
    end

    // Accept each stable change once. All values, including zero, are data.
    // An unchanged input does not generate repeated events.
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            candidate_digit <= 4'd0;
            digit_filtered <= 4'd0;
            stable_count <= '0;
            digit_valid <= 1'b0;
        end
        else
        begin
            digit_valid <= 1'b0;
            if (digit_sync != candidate_digit)
            begin
                candidate_digit <= digit_sync;
                stable_count <= 1;
                // Corner case for 1 cyle debouncing
                if (DEBOUNCE_CYCLES == 1 && digit_sync != digit_filtered)
                begin
                    digit_filtered <= digit_sync;
                    digit_valid <= 1'b1;
                end
            end
            else if (stable_count < DEBOUNCE_CYCLES)
            begin
                stable_count <= stable_count + 1'b1;
                if ((stable_count == (DEBOUNCE_CYCLES - 1)) && (digit_sync != digit_filtered))
                begin
                    digit_filtered <= digit_sync;
                    digit_valid <= 1'b1;
                end
            end
        end
    end

endmodule
