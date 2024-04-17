/*
 * Copyright (c) 2024 Fabio Ramirez Stern
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module SPI_FSM ( // an FSM that stores and controls the transmission modes (reset, i)
    input wire clk, // 1 MHz clock to run the FSM and other loops
    input wire clk_div, // 100 Hz clock to trigger a time to be send out
    input wire res, // reset, active low
    input wire ena,

    input wire [2:0] min_X0, // minutes
    input wire [3:0] min_0X,
    input wire [2:0] sec_X0, // seconds
    input wire [3:0] sec_0X,
    input wire [3:0] ces_X0, // centiseconds (100th)
    input wire [3:0] ces_0X,

    output reg MOSI,
    output reg CS,
    output reg clk_SPI
 );

    reg send_init; // send a setup signal to the MAX display controller (enables BCD mode)
    reg init_complete; // goes high once the setup signal has been fully send
    reg init_reset; // sets init_complete back to 0

    reg send_time;  // send the current time to the display, from the FSM
    wire send_time_ena; // AND of the FSM order and the 100 Hz clock
    assign send_time_ena = send_time & clk_div;
    reg [2:0] current_digit;

    reg send_word;  // send the word in out_word
    reg send_is_busy;
    reg [15:0] out_word;
    reg  [3:0] current_bit;
    
    // FSM
    reg [1:0] state;
    localparam Reset = 2'b00;
    localparam Init  = 2'b01;
    localparam Time  = 2'b10;

    always @(posedge clk_div or negedge res) begin  // FSM
        if (!res) begin // active low reset
            state <= Reset;
        end
        Case(state)
            Reset: begin
                send_time <= 1'b0;
                send_init <= 1'b0;
                init_reset <= 1'b1;
                if (res) begin // once res goes high again: switch to Init
                    state <= Init;
                    init_reset <= 1'b0;
                end
            end
            
            Init: begin
                send_init <= 1'b1;
                if (init_complete) begin
                    send_init <= 1'b0;
                    state <= Time;
                end
            end

            Time: begin
                send_time <= 1'b1;
            end

            default:;
        endcase    
    end

    always @(posedge send_init) begin // creates init to be send
        if (send_init & !init_complete) begin
            out_word <= 16'b0000100111111111;
            send_word <= 1'b1;
        end
    end

    always @(posedge send_time_ena) begin 
        current_digit <= 3'b0;
    end

    always @(posedge clk or posedge init_reset) begin // sends the word
        if (init_reset) begin
            init_complete <= 1'b0;
        end
        if (send_word) begin
            send_is_busy <= 1'b1;
            CS
        end
        else begin
            CS <= 1'b1;
            MOSI <= 1'b0;
            clk_SPI_enable <= 1'b0;
        end
    end

endmodule
