`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/19/2026 10:36:52 PM
// Design Name:
// Module Name: signal_synchronizer
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


// Two-stage synchronizer for a held single-bit level or a registered Gray bus.
// SIGNAL_WIDTH must be positive. This is not a general-purpose data-bus or
// short-pulse synchronizer. Gray buses also need appropriate CDC constraints.
// reset_n asserts asynchronously. synchronous_clear holds both stages at zero
// on destination clock edges until the caller's reset-release logic is ready.
module signal_synchronizer #(
    parameter int SIGNAL_WIDTH = 1
) (
    input  logic                    destination_clock,
    input  logic                    reset_n,
    input  logic                    synchronous_clear,
    input  logic [SIGNAL_WIDTH-1:0] asynchronous_data,
    output logic [SIGNAL_WIDTH-1:0] synchronized_data
);
    // Disable optimization for the synchronization registers.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [SIGNAL_WIDTH-1:0] synchronization_stage1, synchronization_stage2;

    always_ff @(posedge destination_clock or negedge reset_n)
    begin
        if (!reset_n)
        begin
            synchronization_stage1 <= '0;
            synchronization_stage2 <= '0;
        end
        else if (synchronous_clear)
        begin
            synchronization_stage1 <= '0;
            synchronization_stage2 <= '0;
        end
        else
        begin
            synchronization_stage1 <= asynchronous_data;
            synchronization_stage2 <= synchronization_stage1;
        end
    end

    assign synchronized_data = synchronization_stage2;
endmodule
