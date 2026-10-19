`timescale 1ns / 1ps

// Full-system test: MicroBlaze starts capture through GPIO after a button press.
// The associated ELF must use a 320x200 frame and an active-high button.
module tb_stream_processor;
    localparam int FRAME_WIDTH = 320;
    localparam int FRAME_HEIGHT = 200;
    localparam int FRAME_BYTE_COUNT = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int FRAME_WORD_COUNT = FRAME_BYTE_COUNT / 4;
    localparam time SIMULATION_TIMEOUT = 10ms;

    logic system_clock_input = 1'b0;
    logic system_resetn = 1'b0;
    logic pixel_clk = 1'b0;
    logic pixel_resetn = 1'b0;
    logic [7:0] pixel_data = '0;
    logic pixel_valid = 1'b0;
    wire pixel_ready;
    logic button_pressed = 1'b0;

    logic checking_frame = 1'b0;
    logic button_poll_seen = 1'b0;
    logic dma_completion_seen = 1'b0;
    logic dma_length_seen = 1'b0;
    logic dma_read_pending = 1'b0;
    logic [9:0] dma_read_address = '0;
    logic [31:0] last_dma_status = '0;

    int accepted_pixel_count = 0;
    int stream_word_count = 0;
    int memory_word_count = 0;
    int remaining_burst_words = 0;
    int start_count = 0;
    logic previous_start = 1'b0;
    logic previous_word_stalled = 1'b0;
    logic [31:0] stalled_data;
    logic [3:0] stalled_keep;
    logic stalled_last;

    // 100 MHz differential board clock and independent 25 MHz pixel clock.
    always #5 system_clock_input = !system_clock_input;
    always #20 pixel_clk = !pixel_clk;

    stream_processor_wrapper system_under_test (
        .Button_tri_i           (button_pressed),
        .diff_clock_rtl_0_clk_p  (system_clock_input),
        .diff_clock_rtl_0_clk_n  (~system_clock_input),
        .reset_rtl_0            (system_resetn),
        .pixel_clk_0            (pixel_clk),
        .pixel_resetn_0         (pixel_resetn),
        .pixel_data_0           (pixel_data),
        .pixel_valid_0          (pixel_valid),
        .pixel_ready_0          (pixel_ready)
    );

    // Read-only observations; all stimulus enters through wrapper ports.
`define SYSTEM system_under_test.stream_processor_i
`define FRAME_RAM system_under_test.stream_processor_i.axi4_full_ram_0.inst

    wire system_clock = `SYSTEM.microblaze_0_Clk;
    wire peripherals_resetn = `SYSTEM.rst_clk_wiz_1_100M_peripheral_aresetn[0];
    wire receiver_start = `SYSTEM.axi_gpio_0_gpio2_io_o[0];
    wire [31:0] stream_data = `SYSTEM.farme_receiver_0_m_axis_TDATA;
    wire [3:0] stream_keep = `SYSTEM.farme_receiver_0_m_axis_TKEEP;
    wire stream_valid = `SYSTEM.farme_receiver_0_m_axis_TVALID;
    wire stream_ready = `SYSTEM.farme_receiver_0_m_axis_TREADY;
    wire stream_last = `SYSTEM.farme_receiver_0_m_axis_TLAST;

    // Include upper index bits so missing bytes cannot hide after 256 pixels.
    function automatic logic [7:0] expected_pixel(input int pixel_number);
        return 8'((pixel_number * 37) ^ (pixel_number >> 8));
    endfunction

    function automatic logic [31:0] expected_word(input int word_number);
        return {expected_pixel(word_number * 4 + 3),
                expected_pixel(word_number * 4 + 2),
                expected_pixel(word_number * 4 + 1),
                expected_pixel(word_number * 4)};
    endfunction

    // Count only pixels accepted on valid/ready handshakes.
    always @(posedge pixel_clk)
    begin
        if (pixel_resetn && peripherals_resetn)
        begin
            if (!checking_frame && pixel_ready !== 1'b0)
                $fatal(1, "Receiver became ready outside the capture window");

            if (pixel_valid && pixel_ready)
            begin
                if (accepted_pixel_count >= FRAME_BYTE_COUNT)
                    $fatal(1, "Too many accepted pixels");
                accepted_pixel_count++;
            end
        end
    end

    // Verify the receiver stream at the real DMA input.
    always @(posedge system_clock)
    begin
        if (!peripherals_resetn)
        begin
            previous_word_stalled = 1'b0;
            previous_start = 1'b0;
        end
        else
        begin
            if (receiver_start && !previous_start)
            begin
                if (!button_pressed || !checking_frame)
                    $fatal(1, "Start occurred without the expected button press");
                start_count++;
            end
            previous_start = receiver_start;

            if (!checking_frame && stream_valid !== 1'b0)
                $fatal(1, "Unexpected stream output outside the frame");

            if (previous_word_stalled &&
                (stream_valid !== 1'b1 || stream_data !== stalled_data ||
                 stream_keep !== stalled_keep || stream_last !== stalled_last))
                $fatal(1, "AXI4-Stream changed while TREADY was low");

            if (stream_valid && stream_ready)
            begin
                if (stream_word_count >= FRAME_WORD_COUNT)
                    $fatal(1, "Too many AXI4-Stream words");
                if (stream_data !== expected_word(stream_word_count))
                    $fatal(1, "Stream word %0d: got %h expected %h",
                           stream_word_count, stream_data, expected_word(stream_word_count));
                if (stream_keep !== 4'b1111)
                    $fatal(1, "Incorrect TKEEP");
                if (stream_last !== (stream_word_count == FRAME_WORD_COUNT - 1))
                    $fatal(1, "Incorrect TLAST at word %0d", stream_word_count);
                stream_word_count++;
            end

            previous_word_stalled = stream_valid && !stream_ready;
            stalled_data = stream_data;
            stalled_keep = stream_keep;
            stalled_last = stream_last;
        end
    end

    // Check DMA writes at the RAM interface, including burst boundaries.
    always @(posedge system_clock)
    begin
        if (peripherals_resetn)
        begin
            if (`FRAME_RAM.s_axi_awvalid && `FRAME_RAM.s_axi_awready)
            begin
                if (!checking_frame || remaining_burst_words != 0)
                    $fatal(1, "Unexpected RAM write burst");
                if (memory_word_count >= FRAME_WORD_COUNT ||
                    `FRAME_RAM.s_axi_awaddr !== 16'(memory_word_count * 4))
                    $fatal(1, "Incorrect RAM write address: %h", `FRAME_RAM.s_axi_awaddr);
                if (`FRAME_RAM.s_axi_awsize !== 3'd2 ||
                    `FRAME_RAM.s_axi_awburst !== 2'b01)
                    $fatal(1, "Expected 32-bit INCR writes");
                remaining_burst_words = int'(`FRAME_RAM.s_axi_awlen) + 1;
            end

            if (`FRAME_RAM.s_axi_wvalid && `FRAME_RAM.s_axi_wready)
            begin
                if (!checking_frame || remaining_burst_words == 0 ||
                    memory_word_count >= FRAME_WORD_COUNT)
                    $fatal(1, "Unexpected RAM write data");
                if (`FRAME_RAM.s_axi_wdata !== expected_word(memory_word_count))
                    $fatal(1, "RAM input word %0d is incorrect", memory_word_count);
                if (`FRAME_RAM.s_axi_wstrb !== 4'b1111 ||
                    `FRAME_RAM.s_axi_wlast !== (remaining_burst_words == 1))
                    $fatal(1, "Incorrect RAM WSTRB or WLAST");
                remaining_burst_words--;
                memory_word_count++;
            end

            if (`FRAME_RAM.s_axi_bvalid && `FRAME_RAM.s_axi_bready &&
                `FRAME_RAM.s_axi_bresp !== 2'b00)
                $fatal(1, "RAM returned a write error");
        end
    end

    // Observe software polling GPIO and reading the DMA status/length.
    // M01 is DMA AXI-Lite; M02 is GPIO in the current block design.
    always @(posedge system_clock)
    begin
        if (!peripherals_resetn)
        begin
            dma_read_pending <= 1'b0;
        end
        else
        begin
            if (`SYSTEM.axi_smc_M02_AXI_ARVALID && `SYSTEM.axi_smc_M02_AXI_ARREADY &&
                `SYSTEM.axi_smc_M02_AXI_ARADDR == 9'h000)
                button_poll_seen <= 1'b1;

            if (`SYSTEM.axi_smc_M01_AXI_ARVALID && `SYSTEM.axi_smc_M01_AXI_ARREADY)
            begin
                if (dma_read_pending &&
                    !(`SYSTEM.axi_smc_M01_AXI_RVALID && `SYSTEM.axi_smc_M01_AXI_RREADY))
                    $fatal(1, "Unexpected overlapping DMA register reads");
                dma_read_pending <= 1'b1;
                dma_read_address <= `SYSTEM.axi_smc_M01_AXI_ARADDR;
            end

            if (`SYSTEM.axi_smc_M01_AXI_RVALID && `SYSTEM.axi_smc_M01_AXI_RREADY)
            begin
                if (!dma_read_pending)
                    $fatal(1, "DMA read response without an address");
                dma_read_pending <= (`SYSTEM.axi_smc_M01_AXI_ARVALID &&
                                     `SYSTEM.axi_smc_M01_AXI_ARREADY);
                if (`SYSTEM.axi_smc_M01_AXI_RRESP !== 2'b00)
                    $fatal(1, "DMA register read failed");

                if (dma_read_address == 10'h034)
                begin
                    last_dma_status <= `SYSTEM.axi_smc_M01_AXI_RDATA;
                    if ((`SYSTEM.axi_smc_M01_AXI_RDATA & 32'h00004770) != 0)
                        $fatal(1, "DMA reported an error: %h", `SYSTEM.axi_smc_M01_AXI_RDATA);
                    if (checking_frame && `SYSTEM.axi_smc_M01_AXI_RDATA[12])
                        dma_completion_seen <= 1'b1;
                end

                if (checking_frame && dma_read_address == 10'h058)
                begin
                    if (`SYSTEM.axi_smc_M01_AXI_RDATA !== 32'(FRAME_BYTE_COUNT))
                        $fatal(1, "DMA received length is %0d instead of %0d",
                               `SYSTEM.axi_smc_M01_AXI_RDATA, FRAME_BYTE_COUNT);
                    dma_length_seen <= 1'b1;
                end
            end
        end
    end

    // Drive each pixel on a falling edge and hold it until accepted.
    task automatic send_frame;
        for (int pixel_number = 0; pixel_number < FRAME_BYTE_COUNT; pixel_number++)
        begin
            @(negedge pixel_clk);
            pixel_data = expected_pixel(pixel_number);
            pixel_valid = 1'b1;
            do @(posedge pixel_clk); while (pixel_ready !== 1'b1);
        end
        @(negedge pixel_clk);
        pixel_valid = 1'b0;
    endtask

    task automatic send_ignored_pixels;
        for (int pixel_number = 0; pixel_number < 16; pixel_number++)
        begin
            @(negedge pixel_clk);
            pixel_data = 8'(8'hA0 + pixel_number);
            pixel_valid = 1'b1;
        end
        @(negedge pixel_clk);
        pixel_valid = 1'b0;
    endtask

    initial
    begin
        $timeformat(-6, 2, " us", 10);
        repeat (20) @(negedge pixel_clk);
        system_resetn = 1'b1;
        pixel_resetn = 1'b1;

        // Wait until the actual MicroBlaze program starts polling the button.
        wait (peripherals_resetn === 1'b1);
        wait (button_poll_seen);
        $display("MicroBlaze is polling the button at %0t", $time);
        send_ignored_pixels();
        if (accepted_pixel_count != 0 || stream_word_count != 0 || memory_word_count != 0)
            $fatal(1, "Input was captured before the button press");

        @(negedge pixel_clk);
        checking_frame = 1'b1;
        button_pressed = 1'b1;
        wait (receiver_start === 1'b1);
        wait (pixel_ready === 1'b1);
        $display("Capture started through MicroBlaze/GPIO at %0t", $time);
        send_frame();

        wait (dma_completion_seen && dma_length_seen);
        wait (receiver_start === 1'b0);
        repeat (8) @(negedge pixel_clk);
        checking_frame = 1'b0;

        if (accepted_pixel_count != FRAME_BYTE_COUNT ||
            stream_word_count != FRAME_WORD_COUNT ||
            memory_word_count != FRAME_WORD_COUNT || remaining_burst_words != 0)
            $fatal(1, "Incorrect frame length: pixels=%0d stream=%0d RAM=%0d",
                   accepted_pixel_count, stream_word_count, memory_word_count);

        // Read the stored array without modifying RAM or driving its AXI port.
        for (int word_number = 0; word_number < FRAME_WORD_COUNT; word_number++)
        begin
            if (`FRAME_RAM.mem[word_number] !== expected_word(word_number))
                $fatal(1, "RAM word %0d: got %h expected %h", word_number,
                       `FRAME_RAM.mem[word_number], expected_word(word_number));
        end

        // A held button and extra input must not capture another frame.
        send_ignored_pixels();
        repeat (32) @(negedge pixel_clk);
        if (start_count != 1)
            $fatal(1, "Holding the button triggered another capture");

        button_pressed = 1'b0;
        repeat (32) @(negedge pixel_clk);
        if (start_count != 1)
            $fatal(1, "Releasing the button triggered another capture");

        $display("PASS: MicroBlaze + GPIO + receiver + DMA + RAM");
        $display("PASS: %0d bytes, %0d RAM words verified at %0t",
                 FRAME_BYTE_COUNT, FRAME_WORD_COUNT, $time);
        $finish;
    end

    initial
    begin
        #(SIMULATION_TIMEOUT);
        $fatal(1, "System timeout: button_poll=%b start=%b pixels=%0d stream=%0d RAM=%0d DMA=%h",
               button_poll_seen, receiver_start, accepted_pixel_count,
               stream_word_count, memory_word_count, last_dma_status);
    end

`undef FRAME_RAM
`undef SYSTEM
endmodule
