/*
 * Public interface and dimensions of the moving-maximum function.
 */

#ifndef MOVING_MAX_H
#define MOVING_MAX_H

//---------------------------MACROS---------------------------------//
#define SAMPLE_COUNT                 64
#define WINDOW_SIZE                  8

//---------------------------FUNCTION PROTOTYPES--------------------------------//
/**
 * Calculate one output per sample using a window of up to WINDOW_SIZE samples.
 *
 * @param in Input block containing SAMPLE_COUNT integers.
 * @param out Receives SAMPLE_COUNT sliding-window maxima.
 */
void moving_max(int in[SAMPLE_COUNT], int out[SAMPLE_COUNT]);

#endif // MOVING_MAX_H
