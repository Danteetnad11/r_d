`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/15/2026 05:21:14 PM
// Design Name:
// Module Name: tb_lock_controller
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

import lock_pkg::*;

module tb_lock_controller;
    localparam int unsigned TEST_DEBOUNCE_CYCLES = 3;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [3:0] digit_in = 4'd0;
    logic unlocked_led;

    logic filtered_rst = 1'b1;
    logic [3:0] button_digit = 4'd0;
    logic filtered_led;

    // Assignment 1-2: one input digit per clock, without debounce delay.
    lock_controller #(.DEBOUNCE_CYCLES(0)) uut
    (
        .clk(clk),
        .rst(rst),
        .digit_in(digit_in),
        .unlocked_led(unlocked_led)
    );

    // Assignment 3: the same controller with a short simulation filter.
    lock_controller #(.DEBOUNCE_CYCLES(TEST_DEBOUNCE_CYCLES)) filtered_uut
    (
        .clk(clk),
        .rst(filtered_rst),
        .digit_in(button_digit),
        .unlocked_led(filtered_led)
    );

    always #5 clk = ~clk;

    task automatic wait_cycles(input int cycles);
        repeat (cycles)
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Only compare state and LED; stimulus and clock waits are separate.
    task automatic check_state(input LockState expected, input string name);
        if (uut.current_state === expected &&
            unlocked_led === (expected == UNLOCKED))
            $display("[%0t] PASS: %0s; state=%0s, LED=%b",
                     $time, name, expected.name(), unlocked_led);
        else
            begin
                $display("[%0t] FAIL: %0s: expected %0s, got %0s, LED=%b", $time, name, expected.name(), uut.current_state.name(), unlocked_led);
            end
    endtask

    task automatic enter_digit
    (
        input logic [3:0] digit,
        input LockState expected,
        input string name
    );
        // The previous step returns after posedge + #1; avoid an extra clock.
        #1;
        digit_in = digit;
        @(posedge clk);
        #1;
        check_state(expected, name);
    endtask

    task automatic reset_lock;
        // Assert between clock edges to verify asynchronous reset.
        @(posedge clk);
        #1;
        rst = 1'b1;
        digit_in = 4'd0;
        #1;
        check_state(LOCKED, "Asynchronous reset");
        wait_cycles(1);
        rst = 1'b0;
    endtask

    task automatic check_filtered(input LockState expected, input string name);
        if (filtered_uut.current_state === expected &&
            filtered_led === (expected == UNLOCKED))
            $display("[%0t] PASS: debounce: %0s; state=%0s",
                     $time, name, expected.name());
        else
            begin
                $display("[%0t] FAIL: Debounce %0s: expected %0s, got %0s, LED=%b", $time, name, expected.name(), filtered_uut.current_state.name(), filtered_led);
            end
    endtask

    task automatic enter_filtered
    (
        input logic [3:0] digit,
        input LockState expected,
        input string name
    );
        @(posedge clk);
        #1;
        button_digit = digit;
        wait_cycles(TEST_DEBOUNCE_CYCLES + 4);
        check_filtered(expected, name);
    endtask

    initial
    begin

        // ================================================================
        // БЛОК A: uut — контролер БЕЗ debounce, одна цифра на кожен такт.
        // check_state перевіряє стан і LED після кожного переходу.
        // ================================================================

        // СЦЕНАРІЙ 1: правильний код 7 -> 8 -> 9 після reset.
        // Очікуємо: LOCKED -> WAIT_D2 -> WAIT_D3 -> UNLOCKED.
        // LED: 0 у проміжних станах, 1 після третьої цифри.
        reset_lock();
        enter_digit(4'd7, WAIT_D2, "LOCKED -> WAIT_D2: first correct digit");
        enter_digit(4'd8, WAIT_D3, "WAIT_D2 -> WAIT_D3: second correct digit");
        enter_digit(4'd9, UNLOCKED, "WAIT_D3 -> UNLOCKED: third correct digit");

        // СЦЕНАРІЙ 2: утримання розблокованого стану.
        // Початок: UNLOCKED. Подаємо 0 і чекаємо ще два такти.
        // Очікуємо: UNLOCKED і LED=1, доки не буде reset.
        enter_digit(4'd0, UNLOCKED, "UNLOCKED persists with another digit");
        wait_cycles(2);
        check_state(UNLOCKED, "UNLOCKED persists across clock cycles");

        // СЦЕНАРІЙ 3: неправильна ПЕРША цифра.
        // Після reset подаємо 1 замість 7.
        // Очікуємо: залишається LOCKED, LED=0.
        reset_lock();
        enter_digit(4'd1, LOCKED, "Wrong first digit: LOCKED -> LOCKED");

        // СЦЕНАРІЙ 4: неправильна ДРУГА цифра.
        // Після reset: 7 переводить у WAIT_D2, потім 2 замість 8.
        // Очікуємо: WAIT_D2 -> LOCKED, LED=0.
        reset_lock();
        enter_digit(4'd7, WAIT_D2, "Prepare WAIT_D2");
        enter_digit(4'd2, LOCKED, "Wrong second digit: WAIT_D2 -> LOCKED");

        // СЦЕНАРІЙ 5: неправильна ТРЕТЯ цифра.
        // Після reset: 7 -> 8 переводять у WAIT_D3, потім 3 замість 9.
        // Очікуємо: WAIT_D3 -> LOCKED, LED=0.
        reset_lock();
        enter_digit(4'd7, WAIT_D2, "Prepare first digit");
        enter_digit(4'd8, WAIT_D3, "Prepare WAIT_D3");
        enter_digit(4'd3, LOCKED, "Wrong third digit: WAIT_D3 -> LOCKED");

        // СЦЕНАРІЙ 6: повтор першої цифри без debounce.
        // Початок: LOCKED. Подаємо 7, потім ще раз 7 на наступному такті.
        // Очікуємо: WAIT_D2 -> LOCKED, бо друга цифра повинна бути 8.
        enter_digit(4'd7, WAIT_D2, "Start code again");
        enter_digit(4'd7, LOCKED, "Repeated first digit is wrong as second digit");

        // ================================================================
        // БЛОК B: filtered_uut — debounce на 3 стабільні відліки.
        // Цифри подаємо через button_digit; LED — filtered_led.
        // Синхронізатор і реєстр стану додають затримку до цих 3 тактів.
        // ================================================================

        // СЦЕНАРІЙ 7: початковий стан контролера з debounce.
        // Знімаємо filtered_rst; button_digit досі дорівнює 0.
        // Очікуємо: LOCKED, LED=0.
        @(posedge clk);
        #1;
        filtered_rst = 1'b0;
        wait_cycles(TEST_DEBOUNCE_CYCLES + 4);
        check_filtered(LOCKED, "Initial state");

        // СЦЕНАРІЙ 8: короткий імпульс, який імітує брязкіт.
        // Подаємо 7 лише на 2 такти (< 3), потім повертаємо 0.
        // Очікуємо: імпульс відкинуто, стан LOCKED, digit_filtered=0.
        if (TEST_DEBOUNCE_CYCLES > 1)
        begin
            @(posedge clk);
            #1;
            button_digit = 4'd7;
            wait_cycles(TEST_DEBOUNCE_CYCLES - 1);
            button_digit = 4'd0;
            wait_cycles(TEST_DEBOUNCE_CYCLES + 4);
            check_filtered(LOCKED, "Short pulse rejected");
            if (filtered_uut.digit_filtered !== 4'd0)
                begin
                    $display("[%0t] FAIL: Short pulse changed filtered data", $time);
                end
        end

        // СЦЕНАРІЙ 9: стабільна цифра та її тривале утримання.
        // Подаємо 7: до завершення обробки стан ще LOCKED,
        // потім WAIT_D2. Подальше утримання 7 не створює нових введень.
        @(posedge clk);
        #1;
        button_digit = 4'd7;
        wait_cycles(TEST_DEBOUNCE_CYCLES + 2);
        check_filtered(LOCKED, "No early transition");
        wait_cycles(1);
        check_filtered(WAIT_D2, "Stable first digit accepted");
        wait_cycles(2 * TEST_DEBOUNCE_CYCLES + 4);
        check_filtered(WAIT_D2, "Held digit is accepted once");

        // СЦЕНАРІЙ 10: стабільний 0 є звичайною неправильною цифрою.
        // Початок: WAIT_D2, очікується 8. Подаємо 0 достатньо довго.
        // Очікуємо: WAIT_D2 -> LOCKED, LED=0.
        enter_filtered(4'd0, LOCKED, "Stable zero is a wrong second digit");

        // СЦЕНАРІЙ 11: правильний код через debounce.
        // Початок: LOCKED. Кожну цифру 7 -> 8 -> 9 утримуємо до прийняття.
        // Окремо перевіряємо WAIT_D2, WAIT_D3, UNLOCKED і відповідний LED.
        enter_filtered(4'd7, WAIT_D2, "First correct digit");
        enter_filtered(4'd8, WAIT_D3, "Second correct digit");
        enter_filtered(4'd9, UNLOCKED, "Third correct digit");

        // СЦЕНАРІЙ 12: debounce не змінює правило утримання UNLOCKED.
        // Подаємо стабільну 2 після відкриття: стан UNLOCKED, LED=1.
        enter_filtered(4'd2, UNLOCKED, "Unlocked state persists");

        // СЦЕНАРІЙ 13: асинхронний reset після розблокування.
        // Вмикаємо reset через 1 нс після posedge і перевіряємо ДО наступного.
        // Очікуємо: LOCKED, LED=0, digit_filtered=0, digit_valid=0.
        @(posedge clk);
        #1 filtered_rst = 1'b1;
        #1;
        check_filtered(LOCKED, "Asynchronous reset from UNLOCKED");
        if (filtered_uut.digit_filtered !== 4'd0 || filtered_uut.digit_valid !== 1'b0)
            begin
                $display("[%0t] FAIL: Debounce registers did not reset", $time);
            end

        // Усі сценарії виконані; результати дивись у повідомленнях PASS/FAIL вище.
        $display("Tests completed: debounce cycles=%0d", TEST_DEBOUNCE_CYCLES);
        $finish;
    end

endmodule
