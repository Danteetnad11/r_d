`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/19/2026 02:39:23 PM
// Design Name:
// Module Name: farme_receiver
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


// Capture one frame per rising start; ignore new starts while busy.
// Hold pending pixel data until ready. Prepare DMA before start.
// The first accepted byte starts the frame; either reset discards it.
module farme_receiver #(
    parameter int FRAME_WIDTH = 320,
    parameter int FRAME_HEIGHT = 200,
    parameter int FIFO_ADDRESS_WIDTH = 10
)
(
    // External 8-bit pixel stream.
    input  logic        pixel_clk,    // Pixel source clock.
    input  logic        pixel_resetn, // Active-low pixel domain reset.
    input  logic [7:0]  pixel_data,   // One 8-bit pixel.
    input  logic        pixel_valid,  // Source presents a valid pixel.
    output logic        pixel_ready,  // Receiver can accept a pixel.

    // GPIO start command; return low before the next capture.
    input  logic        start,        // Rising edge requests one frame.

    // DMA clock and active-low reset.
    input  logic        aclk,         // AXI4-Stream and DMA clock.
    input  logic        aresetn,      // Active-low AXI domain reset.

    // AXI4-Stream output to DMA.
    output logic [31:0] m_axis_tdata,  // Four packed pixels; first in bits [7:0].
    output logic        m_axis_tvalid, // Output word is valid.
    input  logic        m_axis_tready, // DMA can accept the output word.
    output logic [3:0]  m_axis_tkeep,  // Valid byte lanes; always 4'b1111.
    output logic        m_axis_tlast   // Marks the final word of the frame.
);
    // Default frame: 64000 bytes packed into 16000 words.
    localparam int FRAME_BYTE_COUNT = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int FRAME_WORD_COUNT = FRAME_BYTE_COUNT / 4;
    localparam int PIXEL_COUNTER_WIDTH = (FRAME_BYTE_COUNT > 1) ? $clog2(FRAME_BYTE_COUNT) : 1;
    localparam int WORD_COUNTER_WIDTH = (FRAME_WORD_COUNT > 1) ? $clog2(FRAME_WORD_COUNT) : 1;

    // Only complete four-byte words are supported.
    generate
        if (FRAME_WIDTH <= 0 || FRAME_HEIGHT <= 0 || FRAME_BYTE_COUNT % 4 != 0)
        begin : invalid_frame_dimensions
            initial $error("Frame size must be positive and divisible by four bytes.");
        end
    endgenerate

    // Capture control runs in the pixel clock domain.
    typedef enum logic [1:0] {
        WAITING_FOR_START,
        RECEIVING_FRAME,
        WAITING_FOR_STREAM_COMPLETION
    } capture_state_type;

    // State and control signals for the capture FSM.
    capture_state_type capture_state;
    logic receiver_reset_n;
    logic [PIXEL_COUNTER_WIDTH-1:0] accepted_pixel_count;
    logic pixel_accepted;

    // FIFO status and control signals.
    logic fifo_full, fifo_empty;
    logic fifo_write_reset_busy, fifo_read_reset_busy;
    logic fifo_write_enable, fifo_read_enable;
    logic [7:0] fifo_read_data;

    logic start_in_pixel_domain;
    logic start_previous_pixel_cycle;

    // Each final AXI handshake toggles the completion bit.
    logic stream_completion_toggle;
    logic stream_completion_in_pixel_domain;
    logic acknowledged_completion_toggle;

    // Buffer the first three bytes; the fourth completes the word.
    logic [23:0] packed_pixel_bytes;
    logic [1:0] packing_byte_index;
    logic [WORD_COUNTER_WIDTH-1:0] accepted_word_count;
    logic stream_word_accepted;
    logic output_register_available;

    // Either reset flushes both clock domains.
    assign receiver_reset_n = pixel_resetn && aresetn;
    assign m_axis_tkeep = 4'b1111;

    // Transfer bytes from pixel_clk to aclk.
    my_async_fifo #(
        .DATA_WIDTH    (8),
        .ADDRESS_WIDTH (FIFO_ADDRESS_WIDTH)
    ) pixel_fifo (
        .reset_n        (receiver_reset_n),
        .write_clock    (pixel_clk),
        .write_data     (pixel_data),
        .write_enable   (fifo_write_enable),
        .fifo_full      (fifo_full),
        .write_reset_busy(fifo_write_reset_busy),
        .read_clock     (aclk),
        .read_data      (fifo_read_data),
        .read_enable    (fifo_read_enable),
        .fifo_empty     (fifo_empty),
        .read_reset_busy(fifo_read_reset_busy)
    );

    // Synchronize the GPIO start level into pixel_clk.
    signal_synchronizer #(
        .SIGNAL_WIDTH (1)
    ) start_synchronizer (
        .destination_clock (pixel_clk),
        .reset_n           (receiver_reset_n),
        .synchronous_clear (fifo_write_reset_busy),
        .asynchronous_data (start),
        .synchronized_data (start_in_pixel_domain)
    );

    // Return stream completion to pixel_clk.
    // RAM-write completion must be checked through DMA status.
    signal_synchronizer #(
        .SIGNAL_WIDTH (1)
    ) completion_synchronizer (
        .destination_clock (pixel_clk),
        .reset_n           (receiver_reset_n),
        .synchronous_clear (fifo_write_reset_busy),
        .asynchronous_data (stream_completion_toggle),
        .synchronized_data (stream_completion_in_pixel_domain)
    );

    // Remember synchronized start for rising-edge detection.
    always_ff @(posedge pixel_clk or negedge receiver_reset_n)
    begin
        if (!receiver_reset_n)
        begin
            start_previous_pixel_cycle <= 1'b0;
        end
        else if (fifo_write_reset_busy)
        begin
            start_previous_pixel_cycle <= 1'b0;
        end
        else
        begin
            start_previous_pixel_cycle <= start_in_pixel_domain;
        end
    end

    // Accept pixels only during capture and while FIFO has room.
    assign pixel_ready = receiver_reset_n && !fifo_write_reset_busy && !fifo_full && (capture_state == RECEIVING_FRAME);
    // Count and store bytes only on an input handshake.
    assign pixel_accepted = pixel_valid && pixel_ready;
    assign fifo_write_enable = pixel_accepted;

    // Capture state machine.
    always_ff @(posedge pixel_clk or negedge receiver_reset_n)
    begin
        if (!receiver_reset_n)
        begin
            // Asynchronous reset.
            capture_state <= WAITING_FOR_START;
            accepted_pixel_count <= '0;
            acknowledged_completion_toggle <= 1'b0;
        end
        // Hold initial state until FIFO write reset completes.
        else if (fifo_write_reset_busy)
        begin
            capture_state <= WAITING_FOR_START;
            accepted_pixel_count <= '0;
            acknowledged_completion_toggle <= 1'b0;
        end
        else
        begin
            case (capture_state)
                WAITING_FOR_START:
                begin
                    if (start_in_pixel_domain && !start_previous_pixel_cycle)
                    begin
                        accepted_pixel_count <= '0;
                        capture_state <= RECEIVING_FRAME;
                    end
                end

                RECEIVING_FRAME:
                begin
                    if (pixel_accepted)
                    begin
                        // The current handshake supplies the final frame byte.
                        if (accepted_pixel_count == PIXEL_COUNTER_WIDTH'(FRAME_BYTE_COUNT - 1))
                        begin
                            accepted_pixel_count <= '0;
                            capture_state <= WAITING_FOR_STREAM_COMPLETION;
                        end
                        else
                            accepted_pixel_count <= accepted_pixel_count + 1'b1;
                    end
                end

                WAITING_FOR_STREAM_COMPLETION:
                begin
                    // Wait until DMA accepts the final stream word.
                    if (stream_completion_in_pixel_domain != acknowledged_completion_toggle)
                    begin
                        acknowledged_completion_toggle <= stream_completion_in_pixel_domain;
                        capture_state <= WAITING_FOR_START;
                    end
                end

                default: capture_state <= WAITING_FOR_START;
            endcase
        end
    end

    // Hold AXI output and stop FIFO reads while stalled.
    assign output_register_available = !m_axis_tvalid || m_axis_tready;
    // FWFT data may be consumed only when FIFO is ready and nonempty.
    assign fifo_read_enable = receiver_reset_n && !fifo_read_reset_busy && !fifo_empty && output_register_available;
    assign stream_word_accepted = m_axis_tvalid && m_axis_tready;

    // Pack bytes and drive AXI output registers in the DMA domain.
    always_ff @(posedge aclk or negedge receiver_reset_n)
    begin
        if (!receiver_reset_n)
        begin
            packed_pixel_bytes <= '0;
            packing_byte_index <= '0;
            accepted_word_count <= '0;
            m_axis_tdata <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            stream_completion_toggle <= 1'b0;
        end
        // Keep output inactive until FIFO read reset completes.
        else if (fifo_read_reset_busy)
        begin
            packed_pixel_bytes <= '0;
            packing_byte_index <= '0;
            accepted_word_count <= '0;
            m_axis_tdata <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            stream_completion_toggle <= 1'b0;
        end
        else
        begin
            // Retire output words only on a valid/ready handshake.
            if (stream_word_accepted)
            begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;

                if (m_axis_tlast)
                begin
                    accepted_word_count <= '0;
                    // Use a persistent toggle to cross back into pixel_clk.
                    stream_completion_toggle <= !stream_completion_toggle;
                end
                else
                    accepted_word_count <= accepted_word_count + 1'b1;
            end

            // Pack incoming FIFO bytes into output words.
            if (fifo_read_enable)
            begin
                case (packing_byte_index) // Determine which byte of the pixel to pack
                    2'd0: packed_pixel_bytes[7:0] <= fifo_read_data;
                    2'd1: packed_pixel_bytes[15:8] <= fifo_read_data;
                    2'd2: packed_pixel_bytes[23:16] <= fifo_read_data;
                    2'd3:
                    begin
                        // Place the first pixel in the least-significant byte.
                        m_axis_tdata <= {fifo_read_data, packed_pixel_bytes};
                        m_axis_tvalid <= 1'b1;
                        // Mark the final word of the frame; preserve TLAST while stalled.
                        m_axis_tlast <= (accepted_word_count == WORD_COUNTER_WIDTH'(FRAME_WORD_COUNT - 1));
                    end
                endcase

                packing_byte_index <= packing_byte_index + 1'b1;
            end
        end
    end

endmodule
