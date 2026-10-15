/*
 * Running-light application  for Zybo Z7-20.
 */

//---------------------------INCLUDES----------------------------------//
#include <stdbool.h>
#include <stdint.h>

#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"

#include "xparameters.h"
#include "xgpio.h"
#include "xtmrctr.h"

//---------------------------MACROS---------------------------------//
#define APP_GPIO_CHANNEL             1U
#define APP_GPIO_OUTPUT_DIRECTION    0U
#define APP_TIMER_COUNTER            0U
#define APP_TIME_COUNTER             1U
#define APP_TIMER_RELOAD_TICKS        2U
#define APP_MS_PER_SECOND            1000U

// Build with -DAPP_TIME_SCALE=1000 for accelerated simulation.
#ifndef APP_TIME_SCALE
#define APP_TIME_SCALE               1U
#endif

#if APP_TIME_SCALE < 1
#error "APP_TIME_SCALE must be positive"
#endif

#define APP_TIME_DIVISOR             ((u64)APP_MS_PER_SECOND * APP_TIME_SCALE)

#define APP_BUTTON_COUNT             4U
#define APP_BTN_FASTER_MASK          (1U << 0U)
#define APP_BTN_SLOWER_MASK          (1U << 1U)
#define APP_BTN_PAUSE_MASK           (1U << 2U)
#define APP_BTN_RESUME_MASK          (1U << 3U)
#define APP_BUTTONS_MASK             ((1U << APP_BUTTON_COUNT) - 1U)
#define APP_SPEED_BUTTONS_MASK       (APP_BTN_FASTER_MASK | APP_BTN_SLOWER_MASK)
#define APP_SWITCH_REVERSE_MASK      (1U << 0U)
#define APP_BUTTON_STABILITY_MS      20U

#define APP_INITIAL_LED_INDEX        0U
#define APP_PERIOD_INITIAL_MS        500U
#define APP_PERIOD_MIN_MS            100U
#define APP_PERIOD_MAX_MS            2000U
#define APP_PERIOD_STEP_MS           100U

//---------------------------TYPES-------------------------------------//
// Application state shared by initialization and main-loop callbacks.
typedef struct
{
    u8 led_index;  // 0..3
    u32 period_ms;  // Interval between LED steps, supplied by AXI Timer.
    bool reverse;  // SW0: FALSE = forward, TRUE = backward.
    bool paused;   // FALSE = running, TRUE = paused.
} AppState;

typedef struct
{
    bool candidate; // Candidate state during debounce period.
    bool stable;    // Stable state after debounce period.
    u32 changed_at; // Timer ticks at the last state change.
} ButtonDebounce;

//---------------------------LOCAL VARIABLES--------------------------//
// Peripheral instances persist for the lifetime of the application.
static XGpio buttons_gpio;
static XGpio leds_gpio;
static XGpio switch_gpio;
static XTmrCtr timer;
static u32 debounce_ticks;

//---------------------------LOCAL FUNCTION PROTOTYPES--------------------------//
static int app_init_gpio(const AppState *state);
static int app_init_timer(u32 period_ms);
static int app_init(AppState *state);
static void app_get_time(u32 *ticks);
static bool app_debounce_button(ButtonDebounce *debounce, bool raw);
static void app_restart_timer(u32 period_ms);
static void app_handle_buttons(AppState *state, u32 pressed);
static void app_poll_inputs(AppState *state);
static bool app_poll_timer(void);
static void app_update_led(AppState *state);

//---------------------------LOCAL FUNCTIONS DEFINITIONS-------------------------//
/**
 * Initialize the button, LED, and direction-switch GPIO peripherals.
 * Configure channel 1 on each device and display the initial LED position.
 *
 * @param state Initialized application state containing the initial LED index.
 * @return XST_SUCCESS on success, or the GPIO driver error after reporting it.
 */
static int app_init_gpio(const AppState *state)
{
    int status;

    status = XGpio_Initialize(&buttons_gpio, XPAR_AXI_GPIO_0_BASEADDR);
    if (status != XST_SUCCESS)
    {
        xil_printf("Button GPIO initialization failed: %d\r\n", status);
        return status;
    }

    status = XGpio_Initialize(&leds_gpio, XPAR_AXI_GPIO_1_BASEADDR);
    if (status != XST_SUCCESS)
    {
        xil_printf("LED GPIO initialization failed: %d\r\n", status);
        return status;
    }

    status = XGpio_Initialize(&switch_gpio, XPAR_AXI_GPIO_2_BASEADDR);
    if (status != XST_SUCCESS)
    {
        xil_printf("SW0 GPIO initialization failed: %d\r\n", status);
        return status;
    }

    // Direction bits: 1 = input, 0 = output; BTN[3:0] and SW0 are inputs.
    XGpio_SetDataDirection(&buttons_gpio, APP_GPIO_CHANNEL, APP_BUTTONS_MASK);
    XGpio_SetDataDirection(&leds_gpio, APP_GPIO_CHANNEL, APP_GPIO_OUTPUT_DIRECTION);
    XGpio_SetDataDirection(&switch_gpio, APP_GPIO_CHANNEL, APP_SWITCH_REVERSE_MASK);
    // Illuminate only the LED selected by the initial application state.
    XGpio_DiscreteWrite(&leds_gpio, APP_GPIO_CHANNEL, 1U << state->led_index);
    return XST_SUCCESS;
}

/**
 * Initialize and start AXI Timer counter 0 with a periodic interval.
 * Use the BSP clock frequency and automatic reload with interrupts disabled;
 * expiration can be polled by the main loop.
 * Counter 1 runs continuously upward to measure button debounce intervals.
 *
 * @param period_ms Requested interval in milliseconds.
 * @return XST_SUCCESS on success, a driver error, or XST_INVALID_PARAM if the
 *         interval cannot be represented. Failures are reported before return.
 */
static int app_init_timer(u32 period_ms)
{
    int status;
    u64 period_ticks;
    u64 stability_ticks;

    status = XTmrCtr_Initialize(&timer, XPAR_AXI_TIMER_0_BASEADDR);
    if (status != XST_SUCCESS)
    {
        xil_printf("AXI Timer initialization failed: %d\r\n", status);
        return status;
    }

    // Scale application time intervals; keep the hardware clock unchanged.
    period_ticks = ((u64)timer.Config.SysClockFreqHz * period_ms) / APP_TIME_DIVISOR;
    stability_ticks = ((u64)timer.Config.SysClockFreqHz * APP_BUTTON_STABILITY_MS) /
                      APP_TIME_DIVISOR;
    // Allow for two reload clocks and ensure the load fits the 32-bit counter.
    if (period_ticks < APP_TIMER_RELOAD_TICKS ||
        (period_ticks - APP_TIMER_RELOAD_TICKS) > UINT32_MAX ||
        stability_ticks == 0U || stability_ticks > UINT32_MAX)
    {
        xil_printf("AXI Timer interval configuration failed: %d\r\n",
                   XST_INVALID_PARAM);
        return XST_INVALID_PARAM;
    }
    debounce_ticks = (u32)stability_ticks;

    // Count down and reload automatically on each expiration.
    XTmrCtr_SetOptions(&timer, APP_TIMER_COUNTER, XTC_AUTO_RELOAD_OPTION | XTC_DOWN_COUNT_OPTION);
    // A down-counting auto-reload interval spans the load value plus two clocks.
    XTmrCtr_SetResetValue(&timer, APP_TIMER_COUNTER, (u32)(period_ticks - APP_TIMER_RELOAD_TICKS));
    // Start loads the reset value into counter 0 and enables counting.
    XTmrCtr_Start(&timer, APP_TIMER_COUNTER);

    // Keep debounce timing independent of LED speed changes and pause.
    XTmrCtr_SetOptions(&timer, APP_TIME_COUNTER, XTC_AUTO_RELOAD_OPTION);
    XTmrCtr_SetResetValue(&timer, APP_TIME_COUNTER, 0U);
    XTmrCtr_Start(&timer, APP_TIME_COUNTER);
    return XST_SUCCESS;
}

/**
 * Set the initial running-light state and initialize its peripherals.
 * GPIO is initialized before starting the timer so the initial LED is ready.
 *
 * @param state Application state to initialize.
 * @return XST_SUCCESS on success, or the first peripheral initialization error.
 */
static int app_init(AppState *state)
{
    int status;

    state->led_index = APP_INITIAL_LED_INDEX;
    state->period_ms = APP_PERIOD_INITIAL_MS;
    state->reverse = false;
    state->paused = false;

    status = app_init_gpio(state);
    if (status != XST_SUCCESS)
    {
        return status;
    }

    status |= app_init_timer(state->period_ms);

    return status;
}

/**
 * Read the continuously running timer counter in clock ticks.
 *
 * @param ticks Receives the current 32-bit timestamp.
 */
static void app_get_time(u32 *ticks)
{
    *ticks = XTmrCtr_GetValue(&timer, APP_TIME_COUNTER);
}

/**
 * Debounce one button without blocking and detect a new press.
 *
 * @param debounce Persistent, initially zeroed state for this button.
 * @param raw true when the button is pressed, false when released.
 * @return true for a new press after the configured debounce interval.
 */
static bool app_debounce_button(ButtonDebounce *debounce, bool raw)
{
    u32 now;

    // Ignore repeated reads of the same stable state.
    if (raw == debounce->candidate && raw == debounce->stable)
    {
        return false;
    }

    app_get_time(&now);
    // Record the current time for debounce calculations.
    if (raw != debounce->candidate)
    {
        debounce->candidate = raw;
        debounce->changed_at = now;
        return false;
    }

    // Check if the candidate state has been stable for the required duration.
    if ((u32)(now - debounce->changed_at) >= debounce_ticks)
    {
        debounce->stable = raw;
        return raw;
    }

    return false;
}

/**
 * Restart the initialized AXI Timer with a new interval.
 *
 * @param period_ms Valid interval within the application's period limits.
 */
static void app_restart_timer(u32 period_ms)
{
    // Convert milliseconds to clock ticks without overflowing 32 bits.
    u64 period_ticks = ((u64)timer.Config.SysClockFreqHz * period_ms) / APP_TIME_DIVISOR;

    // Stop the counter before changing its reload value.
    XTmrCtr_Stop(&timer, APP_TIMER_COUNTER);
    XTmrCtr_SetResetValue(&timer, APP_TIMER_COUNTER, (u32)(period_ticks - APP_TIMER_RELOAD_TICKS));
    // Load the new value and begin the new interval.
    XTmrCtr_Start(&timer, APP_TIMER_COUNTER);
}

/**
 * Apply actions for new, debounced button presses.
 * BTN0 speeds up the animation; BTN1 slows it down within the period limits.
 * BTN2 pauses the animation; BTN3 resumes it, taking priority over BTN2.
 *
 * @param state Application state to update.
 * @param pressed Bit mask of new presses, using APP_BTN_*_MASK constants.
 */
static void app_handle_buttons(AppState *state, u32 pressed)
{
    u32 period_ms = state->period_ms;

    if (pressed == 0U)
    {
        return;
    }

    // Opposing speed buttons pressed together leave the interval unchanged.
    if ((pressed & APP_SPEED_BUTTONS_MASK) == APP_BTN_FASTER_MASK && period_ms > APP_PERIOD_MIN_MS)
    {
        period_ms -= APP_PERIOD_STEP_MS;
    }
    else if ((pressed & APP_SPEED_BUTTONS_MASK) == APP_BTN_SLOWER_MASK && period_ms < APP_PERIOD_MAX_MS)
    {
        period_ms += APP_PERIOD_STEP_MS;
    }

    // Pause affects LED stepping; input polling continues to allow resume.
    if (pressed & APP_BTN_PAUSE_MASK)
    {
        state->paused = true;
    }
    // Resume wins if both pause and resume are pressed together.
    if (pressed & APP_BTN_RESUME_MASK) {
        state->paused = false;
    }

    // Restart the timer with the new interval only when the speed changes.
    if (period_ms != state->period_ms)
    {
        app_restart_timer(period_ms);
        state->period_ms = period_ms;
    }
}

/**
 * Poll the direction switch and collect new, debounced button presses.
 * Inputs are serviced on every call, including while the animation is paused.
 *
 * @param state Application state to update from the inputs.
 */
static void app_poll_inputs(AppState *state)
{
    static ButtonDebounce debounce[APP_BUTTON_COUNT];
    u32 buttons;
    u32 pressed = 0U;
    u32 i;

    // Read the state of the reverse switch and update the application state accordingly.
    state->reverse = (XGpio_DiscreteRead(&switch_gpio, APP_GPIO_CHANNEL) & APP_SWITCH_REVERSE_MASK);

    // Read the state of the buttons GPIO.
    buttons = XGpio_DiscreteRead(&buttons_gpio, APP_GPIO_CHANNEL);
    for (i = 0U; i < APP_BUTTON_COUNT; ++i)
    {
        u32 mask = 1U << i;

        if (app_debounce_button(&debounce[i], buttons & mask) == true)
        {
            pressed |= mask;
        }
    }
    // Handle the debounced button presses.
    app_handle_buttons(state, pressed);
}

/**
 * Poll and acknowledge timer expiration independently of application state.
 *
 * @return true if a timer event was acknowledged; otherwise false.
 */
static bool app_poll_timer(void)
{

    // Check if the timer internalinterrupt has occurred.
    u32 control_status = XTmrCtr_ReadReg(timer.BaseAddress, APP_TIMER_COUNTER, XTC_TCSR_OFFSET);
    if ((control_status & XTC_CSR_INT_OCCURED_MASK) == 0U)
    {
        return false;
    }

    // Acknowledge the timer interrupt.
    XTmrCtr_WriteReg(timer.BaseAddress, APP_TIMER_COUNTER, XTC_TCSR_OFFSET,
                     control_status | XTC_CSR_INT_OCCURED_MASK);

    return true;
}

/**
 * Update the LED state in the selected direction while the animation is running.
 *
 * @param state Application state controlling direction, pause, and LED position.
 */
static void app_update_led(AppState *state)
{
    if (!state->paused)
    {
        state->led_index = (state->led_index + (state->reverse ? 3U : 1U)) & 3U;
        XGpio_DiscreteWrite(&leds_gpio, APP_GPIO_CHANNEL, 1U << state->led_index);
    }
}

//---------------------------APPLICATION ENTRY POINT----------------------------//
/**
 * Initialize the application and continuously service inputs and timer events.
 *
 * @return Initialization error on failure; otherwise the main loop runs forever.
 */
int main(void)
{
    AppState state;
    int status;

    xil_printf("Running-light application starting...\r\n");
    status = app_init(&state);
    if (status != XST_SUCCESS)
    {
        return status;
    }

    while (TRUE)
    {
        app_poll_inputs(&state);
        if (app_poll_timer())
        {
            app_update_led(&state);
        }
    }

    return XST_SUCCESS;
}
