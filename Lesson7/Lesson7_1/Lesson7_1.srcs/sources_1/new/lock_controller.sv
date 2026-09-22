`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/15/2026 03:22:53 PM
// Design Name:
// Module Name: lock_controller
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

import lock_pkg::*;

module lock_controller #(
    parameter int unsigned DEBOUNCE_CYCLES = 0 // 0: raw input each clock; >0: required stable samples.
)
(
    input logic clk, // Clock signal
    input logic rst, // Asynchronous reset signal, active high
    input logic [3:0] digit_in, // Raw digit from the physical button encoder
    output logic unlocked_led // High only while the lock is unlocked
);

    // Lock combination codes, entered in this order: 7 -> 8 -> 9.
    localparam logic [3:0] CODE0 = 4'd7;
    localparam logic [3:0] CODE1 = 4'd8;
    localparam logic [3:0] CODE2 = 4'd9;

    // Selected input and acceptance signal: filtered or direct, by parameter.
    logic [3:0] digit_filtered;
    logic digit_valid;

    // Current state is stored in a register; next state is combinational.
    LockState current_state, next_state;

    // Zero selects the assignment's one-digit-per-clock behavior.
    // A positive value enables the separate physical-button filter.
    generate
        if (DEBOUNCE_CYCLES > 0)
        begin : with_debounce
            debounce #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
            ) digit_debounce
            (
                .clk(clk),
                .rst(rst),
                .digit_in(digit_in),
                .digit_filtered(digit_filtered),
                .digit_valid(digit_valid)
            );
        end
        else
        begin : without_debounce
            assign digit_filtered = digit_in;
            assign digit_valid = 1'b1;
        end
    endgenerate

    // Process 1: state register only; asynchronous reset, otherwise copy next_state.
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst)
            current_state <= LOCKED;
        else
            current_state <= next_state;
    end

    // Process 2: next-state logic only; debounce optionally gates acceptance.
    always_comb
    begin
        // Keep the current state while the filter waits for a stable input.
        next_state = current_state;
        if (digit_valid)
        begin
            case (current_state)
                LOCKED:
                begin
                    if (digit_filtered == CODE0) next_state = WAIT_D2;
                    else                        next_state = LOCKED;
                end
                WAIT_D2:
                begin
                    if (digit_filtered == CODE1) next_state = WAIT_D3;
                    else                        next_state = LOCKED;
                end
                WAIT_D3:
                begin
                    if (digit_filtered == CODE2) next_state = UNLOCKED;
                    else                        next_state = LOCKED;
                end
                // Once unlocked, remain unlocked until reset.
                UNLOCKED: next_state = UNLOCKED;
                default:  next_state = LOCKED;
            endcase
        end
    end

    // Process 3: Moore output only; depends on the current state.
    always_comb
    begin
        unlocked_led = (current_state == UNLOCKED);
    end

endmodule
