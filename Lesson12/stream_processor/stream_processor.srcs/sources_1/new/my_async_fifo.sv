`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/19/2026 04:49:39 PM
// Design Name:
// Module Name: my_async_fifo
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


// Dual-clock, first-word-fall-through FIFO.
// FIFO_DEPTH = 2**ADDRESS_WIDTH; ADDRESS_WIDTH must be at least 1.
// read_data is valid only when !fifo_empty && !read_reset_busy.
// read_enable consumes that word.
// One common reset flushes BOTH domains. Assertion is asynchronous; release
// is synchronized internally to each clock. Both clocks must run for release.
// No write/read is accepted while the corresponding reset_busy output is high.
// The asynchronous memory read targets distributed RAM on 7-series devices.
// For implementation, constrain Gray-pointer paths to the first synchronizer
// stages (max delay/bus skew); ASYNC_REG alone is not a timing constraint.
module my_async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDRESS_WIDTH = 10
) (
    // Reset signal (active low)
    input  logic                  reset_n,
    // Write clock domain signals
    input  logic                  write_clock,
    input  logic [DATA_WIDTH-1:0] write_data,
    input  logic                  write_enable,
    output logic                  fifo_full,
    output logic                  write_reset_busy,
    // Read clock domain signals
    input  logic                  read_clock,
    output logic [DATA_WIDTH-1:0] read_data,
    input  logic                  read_enable,
    output logic                  fifo_empty,
    output logic                  read_reset_busy
);
    // Depth of the FIFO
    localparam int FIFO_DEPTH = 1 << ADDRESS_WIDTH;
    // In reflected Gray code, a full-depth offset inverts the top two bits.
    localparam logic [ADDRESS_WIDTH:0] GRAY_FULL_COMPARISON_MASK =
        {2'b11, {(ADDRESS_WIDTH-1){1'b0}}};

    // Memory array for the FIFO storage
    logic [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];

    // Write and read pointers (binary and Gray-coded)
    logic [ADDRESS_WIDTH:0] write_pointer_binary, write_pointer_binary_next;
    logic [ADDRESS_WIDTH:0] read_pointer_binary, read_pointer_binary_next;
    logic [ADDRESS_WIDTH:0] write_pointer_gray, write_pointer_gray_next;
    logic [ADDRESS_WIDTH:0] read_pointer_gray, read_pointer_gray_next;
    // Write and read enable signals after considering FIFO status and reset
    logic write_accepted, read_accepted;

    // Disabling optimization for asynchronous reset synchronizers
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    // Asynchronous reset synchronizer for write and read domains.
    // Ensures that the release of the reset signal is properly synchronized to each clock domain.
    logic [1:0] write_reset_release_stages, read_reset_release_stages;

    // Synchronized Gray pointers received from the opposite clock domain.
    logic [ADDRESS_WIDTH:0] read_pointer_gray_in_write_domain;
    logic [ADDRESS_WIDTH:0] write_pointer_gray_in_read_domain;

    // Synchronize reset release to the write clock.
    always_ff @(posedge write_clock or negedge reset_n)
    begin
        if (!reset_n)
            write_reset_release_stages <= '0;
        else
            write_reset_release_stages <= {write_reset_release_stages[0], 1'b1};
    end

    // Synchronize reset release to the read clock.
    always_ff @(posedge read_clock or negedge reset_n)
    begin
        if (!reset_n)
            read_reset_release_stages <= '0;
        else
            read_reset_release_stages <= {read_reset_release_stages[0], 1'b1};
    end

    // Write and read enable logic considering FIFO status and reset
    assign write_reset_busy = !write_reset_release_stages[1];
    assign read_reset_busy = !read_reset_release_stages[1];
    assign write_accepted = write_enable && !fifo_full && !write_reset_busy;
    assign read_accepted = read_enable && !fifo_empty && !read_reset_busy;
    // Next-state logic for binary and Gray-coded pointers
    assign write_pointer_binary_next = write_pointer_binary + {{ADDRESS_WIDTH{1'b0}}, write_accepted};
    assign read_pointer_binary_next = read_pointer_binary + {{ADDRESS_WIDTH{1'b0}}, read_accepted};
    assign write_pointer_gray_next = (write_pointer_binary_next >> 1) ^ write_pointer_binary_next;
    assign read_pointer_gray_next = (read_pointer_binary_next >> 1) ^ read_pointer_binary_next;

    // Only registered Gray pointers cross clock domains, through two stages.
    signal_synchronizer #(
        .SIGNAL_WIDTH (ADDRESS_WIDTH + 1)
    ) read_pointer_synchronizer (
        .destination_clock (write_clock),
        .reset_n           (reset_n),
        .synchronous_clear (write_reset_busy),
        .asynchronous_data (read_pointer_gray),
        .synchronized_data (read_pointer_gray_in_write_domain)
    );

    signal_synchronizer #(
        .SIGNAL_WIDTH (ADDRESS_WIDTH + 1)
    ) write_pointer_synchronizer (
        .destination_clock (read_clock),
        .reset_n           (reset_n),
        .synchronous_clear (read_reset_busy),
        .asynchronous_data (write_pointer_gray),
        .synchronized_data (write_pointer_gray_in_read_domain)
    );

    // The extra pointer bit distinguishes full from empty after wraparound.
    always_ff @(posedge write_clock or negedge reset_n)
    begin
        if (!reset_n)
        begin
            write_pointer_binary <= '0;
            write_pointer_gray <= '0;
            fifo_full <= 1'b0;
        end
        else if (write_reset_busy)
        begin
            write_pointer_binary <= '0;
            write_pointer_gray <= '0;
            fifo_full <= 1'b0;
        end
        else
        begin
            write_pointer_binary <= write_pointer_binary_next;
            write_pointer_gray <= write_pointer_gray_next;
            fifo_full <= (write_pointer_gray_next ==
                          (read_pointer_gray_in_write_domain ^ GRAY_FULL_COMPARISON_MASK));
        end
    end

    always_ff @(posedge read_clock or negedge reset_n)
    begin
        if (!reset_n)
        begin
            read_pointer_binary <= '0;
            read_pointer_gray <= '0;
            fifo_empty <= 1'b1;
        end
        else if (read_reset_busy)
        begin
            read_pointer_binary <= '0;
            read_pointer_gray <= '0;
            fifo_empty <= 1'b1;
        end
        else
        begin
            read_pointer_binary <= read_pointer_binary_next;
            read_pointer_gray <= read_pointer_gray_next;
            fifo_empty <= (read_pointer_gray_next == write_pointer_gray_in_read_domain);
        end
    end

    // Do not reset RAM contents: resetting pointers makes old data invalid.
    always_ff @(posedge write_clock)
    begin
        if (write_accepted)
            memory[write_pointer_binary[ADDRESS_WIDTH-1:0]] <= write_data;
    end
    // Read from RAM asynchronously
    assign read_data = memory[read_pointer_binary[ADDRESS_WIDTH-1:0]];
endmodule
