`timescale 1ns / 1ps
/*
 * Intentionally broken copy: clips abs(-32768) to 32767 instead of 32768.
 * AXI4-Lite registers: IN=0x00, N=0x04, PEAK=0x08, LEVEL=0x0C.
 */
module sound_level_estimator_broken
(
    //---------------------------INPUTS-----------------------------------------//
    input  logic        clk,              // Clock for the AXI interface and sample history.
    input  logic        reset_n,          // Active-low synchronous reset.

    //---------------------------AXI WRITE ADDRESS------------------------------//
    input  logic [3:0]  s_axi_awaddr,      // Register byte offset.
    input  logic [2:0]  s_axi_awprot,      // Protection attributes; unused by this IP.
    input  logic        s_axi_awvalid,     // Master provides a valid write address.
    output logic        s_axi_awready,     // IP can accept the write address.

    //---------------------------AXI WRITE DATA---------------------------------//
    input  logic [31:0] s_axi_wdata,       // Register write data.
    input  logic [3:0]  s_axi_wstrb,       // One write enable per byte of wdata.
    input  logic        s_axi_wvalid,      // Master provides valid write data.
    output logic        s_axi_wready,      // IP can accept the write data.

    //---------------------------AXI WRITE RESPONSE-----------------------------//
    output logic [1:0]  s_axi_bresp,       // Write response: OKAY or SLVERR.
    output logic        s_axi_bvalid,      // IP provides a valid write response.
    input  logic        s_axi_bready,      // Master can accept the write response.

    //---------------------------AXI READ ADDRESS-------------------------------//
    input  logic [3:0]  s_axi_araddr,      // Register byte offset.
    input  logic [2:0]  s_axi_arprot,      // Protection attributes; unused by this IP.
    input  logic        s_axi_arvalid,     // Master provides a valid read address.
    output logic        s_axi_arready,     // IP can accept the read address.

    //---------------------------AXI READ DATA----------------------------------//
    output logic [31:0] s_axi_rdata,       // Register read data, held until accepted.
    output logic [1:0]  s_axi_rresp,       // Read response: OKAY or SLVERR.
    output logic        s_axi_rvalid,      // IP provides valid read data and response.
    input  logic        s_axi_rready,      // Master can accept the read response.

    //---------------------------LEVEL OUTPUT-----------------------------------//
    output logic [3:0]  level             // Peak divided by 4096, rounded down.
);

    //---------------------------PARAMETERS-------------------------------------//
    localparam int HISTORY_LENGTH = 8; // Maximum number of samples to keep in history.
    localparam logic [3:0] INPUT_ADDRESS  = 4'h0;
    localparam logic [3:0] WINDOW_ADDRESS = 4'h4;
    localparam logic [3:0] PEAK_ADDRESS   = 4'h8;
    localparam logic [3:0] LEVEL_ADDRESS  = 4'hC;
    localparam logic [1:0] RESPONSE_OKAY   = 2'b00;
    localparam logic [1:0] RESPONSE_SLVERR = 2'b10;

    //---------------------------INTERNAL SIGNALS-------------------------------//
    logic [3:0] write_address;
    logic [31:0] write_data;
    logic [3:0] write_strobes;
    logic write_address_pending;
    logic write_data_pending;
    logic register_write;

    logic [15:0] input_register;
    logic signed [15:0] sample_value;
    logic sample_write;
    logic [3:0] window_size;
    logic [31:0] merged_window_size;
    logic [3:0] clamped_window_size;
    logic [HISTORY_LENGTH-1:0] active_sample_mask; // Bit 0 selects the newest sample.
    logic [15:0] sample_magnitude;
    logic [15:0] sample_history [0:HISTORY_LENGTH-1]; // Index 0 holds the newest sample.
    logic [15:0] peak;
    logic [15:0] window_samples [0:HISTORY_LENGTH-1];
    logic [15:0] pair_maximum [0:HISTORY_LENGTH/2-1];
    logic [15:0] group_maximum [0:HISTORY_LENGTH/4-1];

    //---------------------------AXI WRITE HANDSHAKES----------------------------//
    // Buffer the address and data independently; allow one outstanding write.
    assign s_axi_awready = reset_n && !write_address_pending && !s_axi_bvalid;
    assign s_axi_wready = reset_n && !write_data_pending && !s_axi_bvalid;
    assign register_write = reset_n && write_address_pending && write_data_pending && !s_axi_bvalid;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            write_address <= '0;
            write_data <= '0;
            write_strobes <= '0;
            write_address_pending <= 1'b0;
            write_data_pending <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= RESPONSE_OKAY;
        end
        else
        begin
            if (s_axi_awvalid && s_axi_awready)
            begin
                write_address <= s_axi_awaddr;
                write_address_pending <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready)
            begin
                write_data <= s_axi_wdata;
                write_strobes <= s_axi_wstrb;
                write_data_pending <= 1'b1;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (register_write)
            begin
                write_address_pending <= 1'b0;
                write_data_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
                // Only IN and N are writable. Other offsets return an error.
                if (write_address == INPUT_ADDRESS || write_address == WINDOW_ADDRESS)
                    s_axi_bresp <= RESPONSE_OKAY;
                else
                    s_axi_bresp <= RESPONSE_SLVERR;
            end
        end
    end

    //---------------------------BYTE WRITE ENABLES-----------------------------//
    always_comb
    begin
        // Start with stored values; update only the addressed register's bytes.
        sample_value = input_register;
        merged_window_size = {28'b0, window_size};
        sample_write = 1'b0;

        case (write_address)
            INPUT_ADDRESS:
            begin
                // A committed IN write with an enabled sample byte adds one sample.
                sample_write = register_write && (|write_strobes[1:0]);
                for (int byte_index = 0; byte_index < 2; byte_index = byte_index + 1)
                begin
                    if (write_strobes[byte_index])
                        sample_value[byte_index*8 +: 8] = write_data[byte_index*8 +: 8];
                end
            end
            WINDOW_ADDRESS:
            begin
                // Preserve all 32 bits until the new N is clamped to 1..8.
                for (int byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                begin
                    if (write_strobes[byte_index])
                        merged_window_size[byte_index*8 +: 8] = write_data[byte_index*8 +: 8];
                end
            end
            default: begin end
        endcase
    end

    // Decode the new N before its register and the sample mask are updated.
    always_comb
    begin
        if (merged_window_size < 1)
            clamped_window_size = 4'd1;
        else if (merged_window_size > HISTORY_LENGTH)
            clamped_window_size = HISTORY_LENGTH;
        else
            clamped_window_size = merged_window_size[3:0];
    end

    //---------------------------INPUT AND WINDOW REGISTERS----------------------//
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            input_register <= '0;
            window_size <= 4'd4;
            active_sample_mask <= 8'b00001111; // Default N = 4.
        end
        else if (register_write)
        begin
            case (write_address)
                INPUT_ADDRESS:
                begin
                    if (sample_write)
                        input_register <= sample_value;
                end
                WINDOW_ADDRESS:
                begin
                    if (|write_strobes)
                    begin
                        window_size <= clamped_window_size;
                        // Register the mask on the same edge as N; no extra output latency.
                        for (int sample_index = 0; sample_index < HISTORY_LENGTH; sample_index = sample_index + 1)
                        begin
                            active_sample_mask[sample_index] <= (sample_index < clamped_window_size);
                        end
                    end
                end
                default: begin end
            endcase
        end
    end

    //---------------------------AXI READ CHANNEL-------------------------------//
    assign s_axi_arready = reset_n && !s_axi_rvalid;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= '0;
            s_axi_rresp <= RESPONSE_OKAY;
        end
        else
        begin
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (s_axi_arvalid && s_axi_arready)
            begin
                // Capture a snapshot; data remains stable while RREADY is low.
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= RESPONSE_OKAY;
                case (s_axi_araddr)
                    INPUT_ADDRESS:  s_axi_rdata <= '0; // IN is write-only.
                    WINDOW_ADDRESS: s_axi_rdata <= {28'b0, window_size};
                    PEAK_ADDRESS:   s_axi_rdata <= {16'b0, peak};
                    LEVEL_ADDRESS:  s_axi_rdata <= {28'b0, level};
                    default:
                    begin
                        s_axi_rdata <= '0;
                        s_axi_rresp <= RESPONSE_SLVERR;
                    end
                endcase
            end
        end
    end

    //---------------------------SAMPLE MAGNITUDE-------------------------------//
    // Intentional bug: the unsigned magnitude must allow 32768, not clip it.
    assign sample_magnitude = (sample_value == 16'sh8000)
                            ? 16'd32767
                            : (sample_value[15] ? (~sample_value + 16'd1) : sample_value);

    //---------------------------SAMPLE HISTORY---------------------------------//
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            // Clear all entries on a clock edge while reset is active.
            for (int sample_index = 0; sample_index < HISTORY_LENGTH; sample_index = sample_index + 1)
            begin
                sample_history[sample_index] <= '0;
            end
        end
        else if (sample_write)
        begin
            // Move older samples toward the end; discard the oldest entry.
            for (int sample_index = HISTORY_LENGTH - 1; sample_index > 0; sample_index = sample_index - 1)
            begin
                sample_history[sample_index] <= sample_history[sample_index - 1];
            end
            sample_history[0] <= sample_magnitude;
        end
    end

    //---------------------------PEAK CALCULATION-------------------------------//
    always_comb
    begin
        // Exclude older entries without deleting them from history.
        for (int sample_index = 0; sample_index < HISTORY_LENGTH; sample_index = sample_index + 1)
        begin
            window_samples[sample_index] = active_sample_mask[sample_index]
                                        ? sample_history[sample_index] : 16'd0;
        end

        // First stage: eight samples become four pair maximums.
        for (int pair_index = 0; pair_index < HISTORY_LENGTH/2; pair_index = pair_index + 1)
        begin
            pair_maximum[pair_index] = (window_samples[2*pair_index] > window_samples[2*pair_index+1])
                                    ? window_samples[2*pair_index] : window_samples[2*pair_index+1];
        end

        // Second stage: four pair maximums become two group maximums.
        for (int group_index = 0; group_index < HISTORY_LENGTH/4; group_index = group_index + 1)
        begin
            group_maximum[group_index] = (pair_maximum[2*group_index] > pair_maximum[2*group_index+1])
                                      ? pair_maximum[2*group_index] : pair_maximum[2*group_index+1];
        end

        // Third stage: select the maximum of the two groups.
        peak = (group_maximum[0] > group_maximum[1]) ? group_maximum[0] : group_maximum[1];
    end

    //---------------------------LEVEL OUTPUT-----------------------------------//
    // Unsigned division by 4096, rounded down; peak 32768 gives level 8.
    assign level = peak[15:12];

endmodule
