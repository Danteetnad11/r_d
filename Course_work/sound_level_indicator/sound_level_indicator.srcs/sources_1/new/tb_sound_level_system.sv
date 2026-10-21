`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/21/2026 12:28:55 PM
// Design Name:
// Module Name: tb_sound_level_system
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

module tb_sound_level_system;

    //---------------------------TIMING---------------------------------//
    localparam time RESET_DURATION_NS = 2000;
    localparam time SIMULATION_DURATION_NS = 60_000;

    //---------------------------SYSTEM PORTS---------------------------//
    logic input_clock_positive = 1'b0;
    logic input_clock_negative;
    logic reset_n = 1'b0;
    logic [3:0] level;

    sound_level_indicator_wrapper dut
    (
        .diff_clock_rtl_0_clk_p(input_clock_positive),
        .diff_clock_rtl_0_clk_n(input_clock_negative),
        .reset_rtl_0(reset_n),
        .level(level)
    );

    // Generate the 100 MHz differential clock expected by Clocking Wizard.
    always #(5) input_clock_positive = !input_clock_positive;
    assign input_clock_negative = !input_clock_positive;

    // Release the active-low reset; MicroBlaze then executes the associated ELF.
    initial
    begin
        #(RESET_DURATION_NS);
        reset_n = 1'b1;
    end

    // Results are checked in main.c; observe AXI and level in the Waveform viewer.
    initial
    begin
        #(SIMULATION_DURATION_NS);
        $display("[%0d ns] INFO: system simulation finished; inspect AXI waveforms", $time);
        $finish;
    end

endmodule
