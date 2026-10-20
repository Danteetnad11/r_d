/*
 * Sliding-window maximum for a block of 64 integer samples.
 */

//---------------------------INCLUDES----------------------------------//
#include <limits.h>

#include "moving_max.h"

//---------------------------FUNCTION DEFINITIONS-------------------------------//
/**
 * Find the maximum of the current sample and up to seven previous samples.
 * Read each input sample once and keep previous samples in a local window.
 *
 * @param in Input block containing SAMPLE_COUNT integers.
 * @param out Receives SAMPLE_COUNT sliding-window maxima.
 */
void moving_max(int in[SAMPLE_COUNT], int out[SAMPLE_COUNT])
{
    int window[WINDOW_SIZE];

    // Unused positions must not affect frames containing negative values.
INITIALIZE_WINDOW:
    for (int window_index = 0; window_index < WINDOW_SIZE; ++window_index)
    {
        window[window_index] = INT_MIN;
    }

PROCESS_SAMPLES:
    for (int sample_index = 0; sample_index < SAMPLE_COUNT; ++sample_index)
    {
        // Discard the oldest sample and make room for the new one.
    SHIFT_WINDOW:
        for (int window_index = WINDOW_SIZE - 1; window_index > 0; --window_index)
        {
            window[window_index] = window[window_index - 1];
        }

        // Each input element is read exactly once.
        window[0] = in[sample_index];

        int maximum = window[0];
    FIND_MAXIMUM:
        for (int window_index = 1; window_index < WINDOW_SIZE; ++window_index)
        {
            if (window[window_index] > maximum)
            {
                maximum = window[window_index];
            }
        }

        out[sample_index] = maximum;
    }
}
