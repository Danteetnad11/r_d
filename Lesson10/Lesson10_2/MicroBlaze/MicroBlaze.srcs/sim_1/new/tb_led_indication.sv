`timescale 1ns / 1ps


// Match this parameter to APP_TIME_SCALE in the associated Vitis ELF.
module tb_led_indication #(
    parameter int unsigned APP_TIME_SCALE = 1000
);
    localparam time SYSCLK_PERIOD = 8ns; // Zybo Z7-20: 125 MHz.
    localparam time RESET_HOLD = 2us;
    localparam time STARTUP_TIMEOUT = 10ms;

    // These intervals must match the C application compiled into the ELF.
    localparam time INITIAL_PERIOD = 500ms / APP_TIME_SCALE;
    localparam time MIN_PERIOD = 100ms / APP_TIME_SCALE;
    localparam time MAX_PERIOD = 2000ms / APP_TIME_SCALE;
    localparam time PERIOD_STEP = 100ms / APP_TIME_SCALE;
    localparam time DEBOUNCE_PERIOD = 20ms / APP_TIME_SCALE;
    // Allow enough CPU execution time even when the firmware intervals shrink.
    localparam time BUTTON_HOLD = (30ms / APP_TIME_SCALE > 200us)
                               ? 30ms / APP_TIME_SCALE : 200us;
    localparam time BUTTON_RELEASE = BUTTON_HOLD;
    localparam time HELD_BUTTON_TIME = (150ms / APP_TIME_SCALE > 3 * BUTTON_HOLD)
                                    ? 150ms / APP_TIME_SCALE : 3 * BUTTON_HOLD;
    localparam time BOUNCE_PULSE = 2ms / APP_TIME_SCALE;
    localparam time TIMING_TOLERANCE = (2ms / APP_TIME_SCALE > 20us)
                                    ? 2ms / APP_TIME_SCALE : 20us;
    localparam time TEST_TIMEOUT = STARTUP_TIMEOUT + 30s / APP_TIME_SCALE +
                                  100 * BUTTON_HOLD;

    localparam logic [3:0] BTN_FASTER = 4'b0001;
    localparam logic [3:0] BTN_SLOWER = 4'b0010;
    localparam logic [3:0] BTN_PAUSE = 4'b0100;
    localparam logic [3:0] BTN_RESUME = 4'b1000;

    logic sysclk = 1'b0;
    logic reset_rtl_0 = 1'b0; // Active-low external reset.
    logic [3:0] Button_GPIO_tri_i = 4'b0000;
    logic [0:0] Switch_GPIO_tri_i = 1'b0;
    wire [3:0] LED_GPIO_tri_o;

    bit monitor_enabled = 1'b0;
    bit expected_reverse = 1'b0;
    logic [3:0] previous_led = 4'b0001;
    longint unsigned led_steps = 0;
    time last_step_at = 0;

    led_indication_wrapper dut (
        .Button_GPIO_tri_i(Button_GPIO_tri_i),
        .LED_GPIO_tri_o(LED_GPIO_tri_o),
        .Switch_GPIO_tri_i(Switch_GPIO_tri_i),
        .reset_rtl_0(reset_rtl_0),
        .sysclk(sysclk)
    );

    always #(SYSCLK_PERIOD / 2) sysclk = ~sysclk;

    // Check every observable LED step, including changes during button presses.
    always @(LED_GPIO_tri_o) begin : monitor_leds
        logic [3:0] expected_led;
        if (monitor_enabled) begin
            if ($isunknown(LED_GPIO_tri_o) || !$onehot(LED_GPIO_tri_o))
                $fatal(1, "[%0t] Invalid LED value: %b", $time, LED_GPIO_tri_o);

            expected_led = expected_reverse
                ? {previous_led[0], previous_led[3:1]}
                : {previous_led[2:0], previous_led[3]};
            if (LED_GPIO_tri_o !== expected_led)
                $fatal(1, "[%0t] LED step: expected %b, got %b (reverse=%b)",
                       $time, expected_led, LED_GPIO_tri_o, expected_reverse);

            previous_led = LED_GPIO_tri_o;
            last_step_at = $time;
            led_steps = led_steps + 1;
        end
    end

    task automatic wait_steps(input int unsigned count, input time timeout);
        longint unsigned goal;
        goal = led_steps + count;
        fork
            begin
                wait (led_steps >= goal);
            end
            begin
                #(timeout);
                $fatal(1, "[%0t] Timeout waiting for %0d LED steps; check ELF, clock and reset",
                       $time, count);
            end
        join_any
        disable fork;
    endtask

    // Discard the first partial interval, then measure a complete interval.
    task automatic check_period(input time expected_period, input string label_text);
        time first_step_at;
        time measured_period;
        // The first call may start before firmware has finished timer setup.
        wait_steps(1, expected_period + STARTUP_TIMEOUT);
        first_step_at = last_step_at;
        wait_steps(1, expected_period + 2 * TIMING_TOLERANCE);
        measured_period = last_step_at - first_step_at;
        if (measured_period < expected_period - TIMING_TOLERANCE ||
            measured_period > expected_period + TIMING_TOLERANCE)
            $fatal(1, "[%0t] %s: expected period %0t, measured %0t",
                   $time, label_text, expected_period, measured_period);
        $display("[%0t] PASS: %s, period=%0t", $time, label_text, measured_period);
    endtask

    task automatic press_button(input logic [3:0] mask, input time hold_time = BUTTON_HOLD);
        @(negedge sysclk);
        Button_GPIO_tri_i = mask;
        #(hold_time);
        @(negedge sysclk);
        Button_GPIO_tri_i = 4'b0000;
        #(BUTTON_RELEASE);
    endtask

    task automatic check_paused(input time duration);
        longint unsigned saved_steps;
        logic [3:0] saved_led;
        saved_steps = led_steps;
        saved_led = LED_GPIO_tri_o;
        #(duration);
        if (led_steps != saved_steps || LED_GPIO_tri_o !== saved_led)
            $fatal(1, "[%0t] LED changed while paused", $time);
        $display("[%0t] PASS: pause holds LED=%b", $time, saved_led);
    endtask

    initial begin : watchdog
        #(TEST_TIMEOUT);
        $fatal(1, "Global simulation timeout; test did not finish");
    end

    initial begin : stimulus
        time current_period;
        $timeformat(-6, 3, " us", 12);
        if (APP_TIME_SCALE == 0 || BOUNCE_PULSE == 0 ||
            BOUNCE_PULSE >= DEBOUNCE_PERIOD || BUTTON_HOLD <= DEBOUNCE_PERIOD ||
            TIMING_TOLERANCE >= MIN_PERIOD)
            $fatal(1, "Invalid test timing; check APP_TIME_SCALE");
        $display("Starting real-ELF MicroBlaze test: APP_TIME_SCALE=%0d, debounce=%0t",
                 APP_TIME_SCALE, DEBOUNCE_PERIOD);

        #(RESET_HOLD);
        @(negedge sysclk);
        reset_rtl_0 = 1'b1;
        fork
            begin
                wait (LED_GPIO_tri_o === 4'b0001);
            end
            begin
                #(STARTUP_TIMEOUT);
                $fatal(1, "Firmware did not initialize LEDs; associate the Vitis ELF with microblaze_0 in sim_1");
            end
        join_any
        disable fork;

        @(negedge sysclk);
        previous_led = LED_GPIO_tri_o;
        monitor_enabled = 1'b1;
        current_period = INITIAL_PERIOD;
        $display("[%0t] PASS: initial LED=0001", $time);

        check_period(current_period, "initial forward running");
        wait_steps(4, 4 * current_period + 2 * TIMING_TOLERANCE);
        $display("[%0t] PASS: full forward cycle and wraparound", $time);

        // Change direction just after a step, well before the next expiration.
        @(negedge sysclk);
        Switch_GPIO_tri_i[0] = 1'b1;
        expected_reverse = 1'b1;
        wait_steps(4, 4 * current_period + 2 * TIMING_TOLERANCE);
        $display("[%0t] PASS: full reverse cycle and wraparound", $time);

        @(negedge sysclk);
        Switch_GPIO_tri_i[0] = 1'b0;
        expected_reverse = 1'b0;

        press_button(BTN_FASTER);
        current_period = current_period - PERIOD_STEP;
        check_period(current_period, "BTN0 speeds up");

        press_button(BTN_SLOWER);
        current_period = current_period + PERIOD_STEP;
        check_period(current_period, "BTN1 slows down");

        press_button(BTN_FASTER, HELD_BUTTON_TIME);
        current_period = current_period - PERIOD_STEP;
        check_period(current_period, "held BTN0 produces one action");

        // Pulses shorter than the scaled debounce must not change the speed.
        repeat (3)
        begin
            @(negedge sysclk);
            Button_GPIO_tri_i = BTN_FASTER;
            #(BOUNCE_PULSE);
            @(negedge sysclk);
            Button_GPIO_tri_i = 4'b0000;
            #(BOUNCE_PULSE);
        end
        #(BUTTON_RELEASE);
        check_period(current_period, "short pulses and bounce are rejected");

        while (current_period > MIN_PERIOD)
        begin
            press_button(BTN_FASTER);
            current_period = current_period - PERIOD_STEP;
        end
        press_button(BTN_FASTER);
        check_period(MIN_PERIOD, "minimum period clamp");

        press_button(BTN_PAUSE);
        check_paused(3 * current_period + TIMING_TOLERANCE);

        // Direction and speed inputs must still be serviced during pause.
        @(negedge sysclk);
        Switch_GPIO_tri_i[0] = 1'b1;
        expected_reverse = 1'b1;
        press_button(BTN_SLOWER);
        current_period = current_period + PERIOD_STEP;
        check_paused(2 * current_period + TIMING_TOLERANCE);

        press_button(BTN_RESUME);
        check_period(current_period, "resume uses new direction and speed");

        while (current_period < MAX_PERIOD)
        begin
            press_button(BTN_SLOWER);
            current_period = current_period + PERIOD_STEP;
        end
        press_button(BTN_SLOWER);
        check_period(MAX_PERIOD, "maximum period clamp");

        $display("[%0t] PASS: all real-ELF button and LED tests completed (%0d LED steps)",
                 $time, led_steps);
        $finish;
    end
endmodule
