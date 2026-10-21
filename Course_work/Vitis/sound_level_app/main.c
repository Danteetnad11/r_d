/*
 * Sound level estimator verification application for MicroBlaze.
 */

//---------------------------INCLUDES----------------------------------//
#include "xil_io.h"
#include "xparameters.h"
#include "xstatus.h"

//---------------------------MACROS------------------------------------//
#define APP_BASE_ADDRESS        ((UINTPTR)XPAR_SOUND_LEVEL_ESTIMATOR_IP_0_BASEADDR)
#define APP_INPUT_OFFSET        0x00U
#define APP_WINDOW_OFFSET       0x04U
#define APP_PEAK_OFFSET         0x08U
#define APP_LEVEL_OFFSET        0x0CU
#define APP_WINDOW_SIZE         4U

#define APP_ARRAY_LENGTH(array) (sizeof(array) / sizeof((array)[0]))

//---------------------------TYPES-------------------------------------//
typedef enum
{
    APP_TEST_NOT_STARTED = 0,
    APP_TEST_RUNNING,
    APP_TEST_PASSED,
    APP_TEST_FAILED
} AppTestStatus;

//---------------------------GLOBAL VARIABLES--------------------------//
// Watch these variables in the debugger; this system has no UART.
volatile AppTestStatus test_status = APP_TEST_NOT_STARTED;
volatile u32 checked_sample_count = 0U;
volatile s32 last_sample = 0;
volatile u32 last_peak = 0U;
volatile u32 last_level = 0U;

//---------------------------MAIN--------------------------------------//

/**
 * Entry point for the sound level estimator verification application.
 * This function feeds a series of test samples to the sound level estimator IP
 * and verifies that the reported peak and level values match the expected results.
 */
int main(void)
{
    // Show all levels rising, then falling as older peaks leave the N=4 window.
    static const s16 samples[] =
    {
        0, 4096, -8192, 12288, -16384,
        20480, -24576, 28672, -32768, 28672,
        -24576, 20480, -16384, 12288, -8192,
        4096, 0, 0, 0, 0
    };
    static const u32 expected_peaks[] =
    {
        0U, 4096U, 8192U, 12288U, 16384U,
        20480U, 24576U, 28672U, 32768U, 32768U,
        32768U, 32768U, 28672U, 24576U, 20480U,
        16384U, 12288U, 8192U, 4096U, 0U
    };
    static const u32 expected_levels[] =
    {
        0U, 1U, 2U, 3U, 4U,
        5U, 6U, 7U, 8U, 8U,
        8U, 8U, 7U, 6U, 5U,
        4U, 3U, 2U, 1U, 0U
    };

    // Run once after system reset, when the sample history is empty.
    test_status = APP_TEST_RUNNING;
    Xil_Out32(APP_BASE_ADDRESS + APP_WINDOW_OFFSET, APP_WINDOW_SIZE);

    for (u32 sample_index = 0U; sample_index < APP_ARRAY_LENGTH(samples); sample_index++)
    {
        last_sample = samples[sample_index];

        // Preserve the signed sample's 16-bit representation in IN[15:0].
        Xil_Out32(APP_BASE_ADDRESS + APP_INPUT_OFFSET, (u32)(u16)samples[sample_index]);
        last_peak = Xil_In32(APP_BASE_ADDRESS + APP_PEAK_OFFSET);
        last_level = Xil_In32(APP_BASE_ADDRESS + APP_LEVEL_OFFSET);

        if (last_peak != expected_peaks[sample_index] ||
            last_level != expected_levels[sample_index])
        {
            test_status = APP_TEST_FAILED;
            return XST_FAILURE;
        }

        checked_sample_count++;
    }

    test_status = APP_TEST_PASSED;
    return XST_SUCCESS;
}
