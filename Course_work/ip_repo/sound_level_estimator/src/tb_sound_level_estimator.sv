`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/21/2026 12:28:55 PM
// Design Name:
// Module Name: tb_sound_level_estimator
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

/*
 * Verify the complete IP through AXI4-Lite register transactions.
 * Expected algorithm results are listed in Course_work/README.md.
 */
module tb_sound_level_estimator #
(
    parameter bit TEST_BROKEN_MODULE = 1'b0 // Set to 1 to demonstrate the expected FAIL.
);
    //---------------------------SIGNALS----------------------------------------//
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [3:0] s_axi_awaddr = '0;
    logic [2:0] s_axi_awprot = '0;
    logic s_axi_awvalid = 1'b0;
    logic s_axi_awready;
    logic [31:0] s_axi_wdata = '0;
    logic [3:0] s_axi_wstrb = '0;
    logic s_axi_wvalid = 1'b0;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready = 1'b0;
    logic [3:0] s_axi_araddr = '0;
    logic [2:0] s_axi_arprot = '0;
    logic s_axi_arvalid = 1'b0;
    logic s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready = 1'b0;
    logic [3:0] level;
    integer completed_writes = 0;
    integer completed_reads = 0;
    integer current_scenario = 0;

    //---------------------------DESIGN VARIANT AND CLOCK-------------------------------//
    generate
        if (TEST_BROKEN_MODULE)
        begin : broken_design
            sound_level_estimator_broken dut (.*);
        end
        else
        begin : working_design
            sound_level_estimator_ip dut (.*);
        end
    endgenerate

    always #5 clk = !clk; // 100 MHz clock period (10 ns) with 50% duty cycle.

    //---------------------------AXI TASKS--------------------------------------//

    /**
     * Perform an AXI4-Lite write transaction.
     * @param address The 4-bit register address to write to.
     * @param data The 32-bit data to write.
     * @param strobes Byte-enable strobes for the write.
     * @param address_delay Number of clock cycles to wait before asserting AWVALID.
     * @param data_delay Number of clock cycles to wait before asserting WVALID.
     * @param response_delay Number of clock cycles to wait before accepting the write response.
     * @param expected_response The expected write response (2'b00 for OKAY).
     */
    task automatic axi_write
    (
        input logic [3:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes = 4'hF,
        input integer address_delay = 0,
        input integer data_delay = 0,
        input integer response_delay = 0,
        input logic [1:0] expected_response = 2'b00
    );
        begin
            @(negedge clk);
            s_axi_bready = 1'b0;
            fork // Fork to handle address and data channels concurrently.
                begin
                    repeat (address_delay) @(negedge clk); // Wait for the specified address delay before asserting AWVALID.
                    s_axi_awaddr = address;
                    s_axi_awvalid = 1'b1;
                    do @(posedge clk); while (s_axi_awready !== 1'b1); // Wait for AWREADY handshake.
                    @(negedge clk);
                    s_axi_awvalid = 1'b0; // Deassert AWVALID after the address handshake is complete.
                end
                begin
                    repeat (data_delay) @(negedge clk); // Wait for the specified data delay before asserting WVALID.
                    s_axi_wdata = data;
                    s_axi_wstrb = strobes;
                    s_axi_wvalid = 1'b1;
                    do @(posedge clk); while (s_axi_wready !== 1'b1); // Wait for WREADY handshake.
                    @(negedge clk);
                    s_axi_wvalid = 1'b0; // Deassert WVALID after the data handshake is complete.
                end
            join
            // Wait for the write response to become valid.
            do @(posedge clk); while (s_axi_bvalid !== 1'b1);
            if (s_axi_bresp !== expected_response)
                $fatal(1, "[%0d ns] FAIL: write address=%h response=%b expected=%b",
                       $time, address, s_axi_bresp, expected_response);

            // A stalled response must remain valid and must not accept another write.
            repeat (response_delay)
            begin
                @(posedge clk);
                if (s_axi_bvalid !== 1'b1 || s_axi_bresp !== expected_response ||
                    s_axi_awready !== 1'b0 || s_axi_wready !== 1'b0)
                    $fatal(1, "[%0d ns] FAIL: unstable write response", $time);
            end
            @(negedge clk);
            s_axi_bready = 1'b1; // Assert BREADY to accept the write response.
            @(posedge clk);
            @(negedge clk);
            s_axi_bready = 1'b0; // Deassert BREADY after accepting the write response.
            completed_writes = completed_writes + 1;
        end
    endtask

    /**
     * Perform an AXI read transaction.
     * @param address The address to read from.
     * @param expected_data The expected data to be read.
     * @param response_delay The number of cycles to wait for a stable response.
     * @param expected_response The expected AXI response code.
     */
    task automatic axi_read
    (
        input logic [3:0] address,
        input logic [31:0] expected_data,
        input integer response_delay = 0,
        input logic [1:0] expected_response = 2'b00
    );
        begin
            @(negedge clk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b0;
            do @(posedge clk); while (s_axi_arready !== 1'b1); // Wait until the read address is accepted.
            @(negedge clk);
            s_axi_arvalid = 1'b0; // Deassert ARVALID after the read address is accepted.
            do @(posedge clk); while (s_axi_rvalid !== 1'b1); // Wait until the read data is valid.
            // Check if the read data and response match the expected values.
            if (s_axi_rdata !== expected_data || s_axi_rresp !== expected_response)
                $fatal(1, "[%0d ns] FAIL: read address=%h data=%h expected=%h response=%b expected=%b",
                       $time, address, s_axi_rdata, expected_data, s_axi_rresp, expected_response);

            repeat (response_delay)
            begin
                @(posedge clk);
                // Wait for the next clock edge to check the stability of the read response.
                if (s_axi_rvalid !== 1'b1 || s_axi_rdata !== expected_data ||
                    s_axi_rresp !== expected_response || s_axi_arready !== 1'b0)
                    $fatal(1, "[%0d ns] FAIL: unstable read response", $time);
            end
            @(negedge clk);
            s_axi_rready = 1'b1; // Assert RREADY to accept the read data.
            @(posedge clk);
            @(negedge clk);
            s_axi_rready = 1'b0; // Deassert RREADY after accepting the read data.
            completed_reads = completed_reads + 1;
        end
    endtask

    //---------------------------ALGORITHM TASKS--------------------------------//
    /**
     * Task to check the peak and level values against the expected values.
     * @param expected_peak The expected peak value.
     * @param expected_level The expected level value.
     */
    task automatic check_peak(input integer expected_peak, input integer expected_level);
        begin
            axi_read(4'h8, 32'(expected_peak)); // Read the peak value from the corresponding register.
            axi_read(4'hC, 32'(expected_level)); // Read the level value from the corresponding register.
            if (level !== 4'(expected_level))
                $fatal(1, "[%0d ns] FAIL: external level=%0d expected=%0d", $time, level, expected_level); // Check if the external level matches the expected level.
        end
    endtask

    /**
     * Task to reset the design and initialize the AXI signals.
     */
    task automatic reset_design;
        begin
            @(negedge clk);
            reset_n = 1'b0;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            s_axi_bready = 1'b0;
            s_axi_arvalid = 1'b0;
            s_axi_rready = 1'b0;
            repeat (3) @(negedge clk);
            reset_n = 1'b1;
            axi_read(4'h4, 32'd4);
            check_peak(0, 0);
        end
    endtask

    /**
     * Task to submit a sample to the design and check the resulting peak and level values.
     * @param value The sample value to submit.
     * @param expected_peak The expected peak value after submitting the sample.
     * @param expected_level The expected level value after submitting the sample.
     */
    task automatic submit_sample(input integer value, input integer expected_peak, input integer expected_level);
        begin
            axi_write(4'h0, 32'(value));
            check_peak(expected_peak, expected_level);
        end
    endtask

    //---------------------------TEST SEQUENCE----------------------------------//
    initial
    begin
        // Scenario 1: N=4 and expiring peak.
        // This scenario tests the behavior of the design when the peak value expires after N samples.
        current_scenario = 1;
        reset_design();
        axi_write(4'h4, 32'd4);
        submit_sample(100, 100, 0);
        submit_sample(-300, 300, 0);
        submit_sample(50, 300, 0);
        submit_sample(20, 300, 0);
        submit_sample(10, 300, 0);
        submit_sample(5, 50, 0);
        $display("[%0d ns] PASS: scenario 1, N=4 and expiring peak", $time);

        // Scenario 2: Signed limits.
        // This scenario tests the behavior of the design with the maximum and minimum signed values.
        current_scenario = 2;
        reset_design();
        axi_write(4'h4, 32'd1);
        submit_sample(32767, 32767, 7);
        submit_sample(-32768, 32768, 8);
        $display("[%0d ns] PASS: scenario 2, signed limits", $time);

        // Scenario 3: N=3 and mixed samples.
        // This scenario tests the behavior of the design with a mix of positive and negative samples and a window size of 3.
        current_scenario = 3;
        reset_design();
        axi_write(4'h4, 32'd3);
        submit_sample(0, 0, 0);
        submit_sample(16384, 16384, 4);
        submit_sample(32767, 32767, 7);
        submit_sample(16384, 32767, 7);
        submit_sample(0, 32767, 7);
        submit_sample(-16384, 16384, 4);
        submit_sample(-32768, 32768, 8);
        $display("[%0d ns] PASS: scenario 3, N=3 and mixed samples", $time);

        // Scenario 4: N clamping to the supported range 1..8.
        current_scenario = 4;
        reset_design();
        axi_write(4'h4, 32'd0);
        axi_read(4'h4, 32'd1);
        axi_write(4'h4, 32'd1);
        axi_read(4'h4, 32'd1);
        axi_write(4'h4, 32'd8);
        axi_read(4'h4, 32'd8);
        axi_write(4'h4, 32'd9);
        axi_read(4'h4, 32'd8);
        axi_write(4'h4, 32'd16);
        axi_read(4'h4, 32'd8);
        axi_write(4'h4, 32'hFFFFFFFF);
        axi_read(4'h4, 32'd8);
        $display("[%0d ns] PASS: N clamping", $time);

        // Scenario 5: Read-only registers and invalid offsets.
        // This scenario tests the behavior of the design when accessing read-only registers and invalid offsets.
        current_scenario = 5;
        reset_design();
        submit_sample(100, 100, 0);
        axi_write(4'h8, 32'hFFFFFFFF, 4'hF, 0, 0, 0, 2'b10);
        axi_write(4'hC, 32'hFFFFFFFF, 4'hF, 0, 0, 0, 2'b10);
        axi_write(4'h2, 32'hFFFFFFFF, 4'hF, 0, 0, 0, 2'b10);
        check_peak(100, 0);
        axi_read(4'h0, 32'd0);
        axi_read(4'h2, 32'd0, 3, 2'b10);
        $display("[%0d ns] PASS: read-only registers and invalid offsets", $time);

        // Scenario 6: Level boundaries.
        // This scenario tests the behavior of the design at the boundaries of different levels.
        current_scenario = 6;
        reset_design();
        axi_write(4'h4, 32'd1);
        submit_sample(0, 0, 0);
        submit_sample(4095, 4095, 0);
        submit_sample(4096, 4096, 1);
        submit_sample(8191, 8191, 1);
        submit_sample(8192, 8192, 2);
        submit_sample(28671, 28671, 6);
        submit_sample(28672, 28672, 7);
        submit_sample(32767, 32767, 7);
        submit_sample(-32768, 32768, 8);
        $display("[%0d ns] PASS: level boundaries", $time);

        // Scenario 7: Full history and peak expiration.
        // This scenario tests the behavior of the design when the history is full and peaks expire.
        current_scenario = 7;
        reset_design();
        axi_write(4'h4, 32'd8);
        submit_sample(-32768, 32768, 8);
        repeat (7) submit_sample(0, 32768, 8);
        submit_sample(0, 0, 0);
        $display("[%0d ns] PASS: full history and peak expiration", $time);

        $display("[%0d ns] PASS: all scenarios, %0d AXI writes and %0d AXI reads checked",
                 $time, completed_writes, completed_reads);
        $finish;
    end

    // Stop a stalled transaction instead of running indefinitely.
    initial
    begin
        #100000;
        $fatal(1, "[%0d ns] FAIL: timeout in scenario %0d", $time, current_scenario);
    end
endmodule

