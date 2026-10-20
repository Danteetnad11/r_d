/*
 * Compare moving_max with a direct sliding-window reference.
 */

//---------------------------INCLUDES----------------------------------//
#include <limits.h>
#include <stdint.h>
#include <stdio.h>

#include "moving_max.h"

//---------------------------LOCAL FUNCTION PROTOTYPES--------------------------//
static void reference_maximum(const int in[SAMPLE_COUNT], int out[SAMPLE_COUNT]);
static int check_vector(const char *name, int in[SAMPLE_COUNT]);

//---------------------------LOCAL FUNCTION DEFINITIONS--------------------------//
/**
 * Calculate each result directly from the available input samples.
 *
 * @param in Input block containing SAMPLE_COUNT integers.
 * @param out Receives the independently calculated reference results.
 */
static void reference_maximum(const int in[SAMPLE_COUNT], int out[SAMPLE_COUNT])
{
    for (int sample_index = 0; sample_index < SAMPLE_COUNT; ++sample_index)
    {
        int first_index = sample_index >= WINDOW_SIZE - 1
                        ? sample_index - WINDOW_SIZE + 1 : 0;
        int maximum = in[first_index];

        for (int window_index = first_index + 1; window_index <= sample_index; ++window_index)
        {
            if (in[window_index] > maximum)
            {
                maximum = in[window_index];
            }
        }

        out[sample_index] = maximum;
    }
}

/**
 * Check all 64 outputs against the reference.
 *
 * @param name Test name displayed in the result message.
 * @param in Input vector passed to the function under test.
 * @return 0 on success, 1 on the first mismatch.
 */
static int check_vector(const char *name, int in[SAMPLE_COUNT])
{
    int expected[SAMPLE_COUNT];
    int actual[SAMPLE_COUNT];

    reference_maximum(in, expected);

    // Start with incorrect values so missing output writes are detected.
    for (int sample_index = 0; sample_index < SAMPLE_COUNT; ++sample_index)
    {
        actual[sample_index] = expected[sample_index] == INT_MIN ? INT_MAX : INT_MIN;
    }

    moving_max(in, actual);

    for (int sample_index = 0; sample_index < SAMPLE_COUNT; ++sample_index)
    {
        if (actual[sample_index] != expected[sample_index])
        {
            printf("FAIL: %s, index=%d, expected=%d, actual=%d\n",
                   name, sample_index, expected[sample_index], actual[sample_index]);
            return 1;
        }
    }

    printf("PASS: %s\n", name);
    return 0;
}

//---------------------------TESTBENCH ENTRY POINT------------------------------//
/**
 * Run eight vectors, including repeated calls with different input data.
 *
 * @return 0 if every vector passes, otherwise 1.
 */
int main(void)
{
    int input[SAMPLE_COUNT];
    int failure_count = 0;
    uint32_t random_state = UINT32_C(12345);
    const int extreme_pattern[WINDOW_SIZE] =
    {
        INT_MIN, INT_MIN + 1, -1, INT_MAX,
        0, INT_MAX - 1, INT_MIN, -7
    };

    // Check increasing sequence.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = index - 32;
    }
    failure_count += check_vector("increasing", input);

    // Check decreasing sequence.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = SAMPLE_COUNT - index;
    }
    failure_count += check_vector("decreasing", input);

    // A negative frame after positive data also checks window initialization.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = -1 - ((index * 17) % 97);
    }
    failure_count += check_vector("negative values", input);

    // Check constant values.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = -11;
    }
    failure_count += check_vector("constant values", input);

    // Check expiring maxima and repeated equal maxima.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = -50;
    }
    input[0] = 1000;
    input[7] = 900;
    input[31] = 1200;
    input[32] = 1200;
    failure_count += check_vector("expiring and repeated maxima", input);

    // Check extreme values with INT_MIN and INT_MAX.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = extreme_pattern[index % WINDOW_SIZE];
    }
    failure_count += check_vector("INT_MIN and INT_MAX", input);

    // Check all INT_MIN values.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        input[index] = INT_MIN;
    }
    failure_count += check_vector("all INT_MIN", input);

    // A fixed seed makes the mixed vector repeatable in C and RTL simulation.
    for (int index = 0; index < SAMPLE_COUNT; ++index)
    {
        random_state = random_state * UINT32_C(1664525) + UINT32_C(1013904223);
        input[index] = (int)(random_state % UINT32_C(201)) - 100;
    }
    failure_count += check_vector("mixed values", input);

    if (failure_count != 0)
    {
        printf("FAIL: %d of 8 vectors failed\n", failure_count);
        return 1;
    }

    printf("PASS: all 8 vectors, 512 outputs checked\n");
    return 0;
}
