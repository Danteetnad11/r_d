`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/15/2026 03:36:24 PM
// Design Name:
// Module Name: lock
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


package lock_pkg;
    typedef enum logic[1:0]
    {
        LOCKED,
        WAIT_D2,
        WAIT_D3,
        UNLOCKED
    } LockState;
endpackage
