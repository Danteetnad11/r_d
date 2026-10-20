`timescale 1ns / 1ps

/*
 * Verify the packaged HLS IP using synchronous input and output memories.
 * Run eight input vectors and compare all 64 outputs with a direct reference.
 */
module tb_moving_max;
    //---------------------------PARAMETERS-------------------------------------//
    localparam integer SAMPLE_COUNT = 64;
    localparam integer WINDOW_SIZE = 8;
    localparam signed [31:0] MINIMUM_INT = 32'sh80000000;
    localparam signed [31:0] MAXIMUM_INT = 32'sh7fffffff;

    //---------------------------SIGNALS----------------------------------------//
    logic ap_clk = 1'b0;    // 100 MHz IP clock.
    logic ap_rst = 1'b1;    // Active-high synchronous reset.
    logic ap_start = 1'b0;  // Hold until the IP acknowledges completion.
    logic ap_done;          // The current block of 64 samples is complete.
    logic ap_idle;          // The IP is waiting for a start command.
    logic ap_ready;         // The IP can accept another transaction.

    logic [5:0] input_address;          // Input memory index: 0..63.
    logic input_read_enable;            // Request an input memory read.
    logic signed [31:0] input_data = 0; // Registered memory response to the IP.

    logic [5:0] output_address;       // Output memory index: 0..63.
    logic output_enable;             // Output memory port is enabled.
    logic output_write_enable;       // Write only when both enables are high.
    logic signed [31:0] output_data;  // Moving maximum produced by the IP.

    // Signed samples preserve negative values during comparisons and printing.
    logic signed [31:0] input_memory [0:SAMPLE_COUNT-1];
    logic signed [31:0] output_memory [0:SAMPLE_COUNT-1];
    logic signed [31:0] expected_memory [0:SAMPLE_COUNT-1]; // Reference results.

    // Per-address counters detect missing reads and missing or duplicate writes.
    integer reads_per_address [0:SAMPLE_COUNT-1];
    integer writes_per_address [0:SAMPLE_COUNT-1];
    integer input_read_count = 0; // Includes unused pipeline-drain reads.
    integer output_write_count = 0;
    integer current_vector = 0;
    integer completed_vectors = 0;
    logic checking_vector = 1'b0; // Memory accesses are allowed during a test only.

    //---------------------------DESIGN UNDER TEST------------------------------//
    moving_max_pipeline_0 dut (
        .ap_clk         (ap_clk),
        .ap_rst         (ap_rst),
        .ap_start       (ap_start),
        .ap_done        (ap_done),
        .ap_idle        (ap_idle),
        .ap_ready       (ap_ready),
        .in_r_address0  (input_address),
        .in_r_ce0       (input_read_enable),
        .in_r_q0        (input_data),
        .out_r_address0 (output_address),
        .out_r_ce0      (output_enable),
        .out_r_we0      (output_write_enable),
        .out_r_d0       (output_data)
    );

    //---------------------------CLOCK AND MEMORY MODELS------------------------//
    always #5 ap_clk = !ap_clk;

    // Synchronous read: a request supplies data for the following clock edge.
    always @(posedge ap_clk)
    begin
        if (ap_rst)
        begin
            input_data <= 0;
        end
        else if (input_read_enable)
        begin
            // Reduction XOR becomes X if any address bit contains X or Z.
            if (!checking_vector || (^input_address) === 1'bx)
                $fatal(1, "Unexpected input read");
            // The first 64 requests must read samples in order.
            // Generated HLS RTL may issue unused reads while draining the pipeline.
            if (input_read_count < SAMPLE_COUNT && input_address !== 6'(input_read_count))
                $fatal(1, "Vector %0d: input address %0d, expected %0d",
                       current_vector, input_address, input_read_count);

            // Update after this edge; the IP can consume the value on the next edge.
            // With read enable low, input_data retains its previous value.
            input_data <= input_memory[input_address];
            reads_per_address[input_address] = reads_per_address[input_address] + 1;
            input_read_count = input_read_count + 1;
        end
    end

    // Store and check every output write at the memory interface.
    always @(posedge ap_clk)
    begin
        if (!ap_rst && output_enable && output_write_enable)
        begin
            if (!checking_vector || (^output_address) === 1'bx)
                $fatal(1, "Unexpected output write");
            // Each output address must be written exactly once per vector.
            if (writes_per_address[output_address] != 0)
                $fatal(1, "Vector %0d: duplicate output address %0d",
                       current_vector, output_address);
            // Case inequality also reports unknown output bits as a mismatch.
            if (output_data !== expected_memory[output_address])
                $fatal(1, "Vector %0d, index %0d: got %0d expected %0d",
                       current_vector, output_address, output_data,
                       expected_memory[output_address]);

            output_memory[output_address] <= output_data;
            writes_per_address[output_address] = writes_per_address[output_address] + 1;
            output_write_count = output_write_count + 1;
        end
    end

    //---------------------------LOCAL TASKS------------------------------------//
    // Calculate the reference directly from in[max(0,n-7)..n].
    task automatic calculate_reference;
        integer sample_index;
        integer window_index;
        integer first_index;
        logic signed [31:0] maximum;
        begin
            for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1)
            begin
                // Before sample 7, the window contains only samples 0..sample_index.
                first_index = sample_index >= WINDOW_SIZE - 1
                            ? sample_index - WINDOW_SIZE + 1 : 0;
                maximum = input_memory[first_index];

                // Scan the original input independently of the IP implementation.
                for (window_index = first_index + 1;
                     window_index <= sample_index; window_index = window_index + 1)
                begin
                    if (input_memory[window_index] > maximum)
                        maximum = input_memory[window_index];
                end
                expected_memory[sample_index] = maximum;
            end
        end
    endtask

    // Generate the same eight vectors used by the C testbench.
    // 0: Increasing sequence
    // 1: Decreasing sequence
    // 2: Negative values
    // 3: Equal values
    // 4: Flat background with isolated peaks
    // 5: Signed limits and nearby values
    // 6: Random values
    // 7: Mixed pattern
    task automatic prepare_input;
        input integer vector_number;
        integer sample_index;
        logic [31:0] random_state;
        begin
            random_state = 32'd12345; // Fixed seed makes the mixed vector repeatable.
            for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1)
            begin
                case (vector_number)
                    // Increasing: the newest sample is always the maximum.
                    0: input_memory[sample_index] = sample_index - 32;
                    // Decreasing: the maximum changes as the oldest sample expires.
                    1: input_memory[sample_index] = SAMPLE_COUNT - sample_index;
                    // Negative values expose incorrect unsigned comparisons or zero initialization.
                    2: input_memory[sample_index] = -1 - ((sample_index * 17) % 97);
                    // Equal values check repeated maxima.
                    3: input_memory[sample_index] = -11;
                    // Start with a flat background; insert isolated peaks below.
                    4: input_memory[sample_index] = -50;
                    // Repeat signed limits and nearby values in each group of eight.
                    5:
                    begin
                        case (sample_index % WINDOW_SIZE)
                            0: input_memory[sample_index] = MINIMUM_INT;
                            1: input_memory[sample_index] = MINIMUM_INT + 1;
                            2: input_memory[sample_index] = -1;
                            3: input_memory[sample_index] = MAXIMUM_INT;
                            4: input_memory[sample_index] = 0;
                            5: input_memory[sample_index] = MAXIMUM_INT - 1;
                            6: input_memory[sample_index] = MINIMUM_INT;
                            7: input_memory[sample_index] = -7;
                        endcase
                    end
                    // The smallest possible input must also be a valid maximum.
                    6: input_memory[sample_index] = MINIMUM_INT;
                    7:
                    begin
                        // A 32-bit pseudo-random sequence mapped to -100..100.
                        random_state = random_state * 32'd1664525 + 32'd1013904223;
                        input_memory[sample_index] = $signed(random_state % 32'd201) - 100;
                    end
                    default: $fatal(1, "Unknown test vector");
                endcase
            end

            if (vector_number == 4)
            begin
                // The first peak leaves the window at sample 8.
                input_memory[0] = 1000;
                input_memory[7] = 900;
                // Equal peaks keep the maximum at 1200 until both have expired.
                input_memory[31] = 1200;
                input_memory[32] = 1200;
            end
        end
    endtask

    // Start one block and verify all memory transfers and stored results.
    task automatic check_vector;
        input [8*48-1:0] vector_name; // Up to 48 characters for the PASS message.
        integer sample_index;
        begin
            // Drive controls on falling edges to avoid races with the IP clock edge.
            @(negedge ap_clk);
            while (ap_idle !== 1'b1)
                @(negedge ap_clk);

            // Prepare expected values and clear the testbench state for this vector.
            calculate_reference();
            input_read_count = 0;
            output_write_count = 0;
            for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1)
            begin
                reads_per_address[sample_index] = 0;
                writes_per_address[sample_index] = 0;
                output_memory[sample_index] = 'x; // Unwritten locations stay unknown.
            end

            // Enable memory checks before starting the IP.
            checking_vector = 1'b1;
            ap_start = 1'b1;
            // Sample completion on a rising edge, then lower start safely.
            do @(posedge ap_clk); while (ap_done !== 1'b1);
            if (ap_ready !== 1'b1)
                $fatal(1, "IP completed without asserting ap_ready");

            @(negedge ap_clk);
            ap_start = 1'b0;
            // Allow final memory updates and the return to idle to settle.
            repeat (2) @(negedge ap_clk);

            // Extra unused input requests are allowed; exactly 64 outputs are required.
            if (input_read_count < SAMPLE_COUNT || output_write_count != SAMPLE_COUNT)
                $fatal(1, "Vector %0d: reads=%0d writes=%0d, expected at least 64 reads and 64 writes",
                       current_vector, input_read_count, output_write_count);

            // Check every location, including any that received no write at all.
            for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1)
            begin
                if (reads_per_address[sample_index] < 1 ||
                    writes_per_address[sample_index] != 1 ||
                    output_memory[sample_index] !== expected_memory[sample_index])
                    $fatal(1, "Vector %0d: memory check failed at index %0d",
                           current_vector, sample_index);
            end

            checking_vector = 1'b0;
            completed_vectors = completed_vectors + 1;
            $display("PASS: %0s, %0d RAM reads and 64 outputs checked at %0t",
                     vector_name, input_read_count, $time);
        end
    endtask

    //---------------------------TEST SEQUENCE----------------------------------//
    initial
    begin
        $timeformat(-6, 2, " us", 10); // Print simulation timestamps in microseconds.
        // Hold reset for five clock cycles and release it on a falling edge.
        repeat (5) @(negedge ap_clk);
        ap_rst = 1'b0;

        // Do not reset between vectors: each new call must reinitialize its window.
        for (current_vector = 0; current_vector < 8; current_vector = current_vector + 1)
        begin
            prepare_input(current_vector);
            case (current_vector)
                0: check_vector("increasing");
                1: check_vector("decreasing");
                2: check_vector("negative values");
                3: check_vector("constant values");
                4: check_vector("expiring and repeated maxima");
                5: check_vector("INT_MIN and INT_MAX");
                6: check_vector("all INT_MIN");
                7: check_vector("mixed values");
            endcase
        end

        $display("PASS: all %0d vectors, 512 outputs checked", completed_vectors);
        $finish;
    end

    // Stop a stalled test instead of waiting indefinitely.
    initial
    begin
        #100000; // Wait 100 us before reporting a timeout.
        $fatal(1, "Test timed out: vector=%0d reads=%0d writes=%0d",
               current_vector, input_read_count, output_write_count);
    end
endmodule
