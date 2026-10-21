`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/21/2026 12:28:55 PM
// Design Name:
// Module Name: sound_level_estimator_ip
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
// Top-level wrapper for the sound level estimator IP.
// Connects AXI interface signals to the internal estimator module.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

/*
 * Verilog top level for IP Packager.
 * All registers, AXI handshakes, and calculations remain in the SystemVerilog module.
 */
module sound_level_estimator_ip
(
    //---------------------------CLOCK AND RESET--------------------------------//
    input  wire        clk,
    input  wire        reset_n,

    //---------------------------AXI WRITE ADDRESS------------------------------//
    input  wire [3:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    //---------------------------AXI WRITE DATA---------------------------------//
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    //---------------------------AXI WRITE RESPONSE-----------------------------//
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    //---------------------------AXI READ ADDRESS-------------------------------//
    input  wire [3:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    //---------------------------AXI READ DATA----------------------------------//
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    //---------------------------LEVEL OUTPUT-----------------------------------//
    output wire [3:0]  level
);

    // Connect each external port directly to the existing estimator.
    sound_level_estimator estimator
    (
        .clk           (clk),
        .reset_n       (reset_n),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .level         (level)
    );

endmodule
