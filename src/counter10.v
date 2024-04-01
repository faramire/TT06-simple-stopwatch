/*
 * Copyright (c) 2024 Fabio Ramirez Stern
 * SPDX-License-Identifier: Apache-2.0
 ******************************************************
 * Counts up to 10
 */

`define default_netname none

module counter10 (
    input  wire      clk, // clock
    input  wire      ena, // enable
    input  wire      res, // reset, active low
    output reg       max, // high when max value (10) reached
    output reg [3:0] cnt  // 3 bit counter output
 );

    reg[3:0] counter    = 0;
    parameter max_count = 10;

    always @(posedge clk or negedge res) begin
        if (!res) begin
            cnt <= 0;
            max <= 0;
        end else if (ena) begin
            if (cnt < (max_count-1)) begin
                cnt <= cnt + 1;
            end else begin
                cnt <= 0;
            end

          if (cnt == max_count-2) begin
            	max <= 1;
            end else begin
                max <= 0;
            end
        end
    end

endmodule