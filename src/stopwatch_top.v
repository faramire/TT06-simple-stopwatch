/*
 * Copyright (c) 2024 Fabio Ramirez Stern
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

// ui_in [0]: reset: resets the stopwatch to 00:00:00
// ui_in [1]: speed: 

module tt_um_faramire_stopwatch (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
 );
  // All output pins must be assigned. If not used, assign to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;
  assign uo_out[7:3]  = 0;

  wire dividedClock; // 100 Hz clock
  wire counter_enable;
  wire display_enable;
  wire reset_either; // an OR of the input reset and the chip wide reset, for those that shall be affected by both
  wire clock_enable; // and AND of the clock with the counter enable,
                     // so that the clock divider doesn't advance when the counters are halted

  assign reset_either = rst_n | (~ui_in[2]);
  assign clock_enable = counter_enable & clk;

  wire [2:0] min_X0; // all the results of the counter chain
  wire [3:0] min_0X;
  wire [2:0] sec_X0;
  wire [3:0] sec_0X;
  wire [3:0] ces_X0;
  wire [3:0] ces_0X;

  clockDivider clockDivider1 ( // divides the 100 MHz clock to 100 Hz
    .clk_in  (clock_enable),
    .res     (reset_either),
    .clk_out (dividedClock)
  );

  controller controller1 ( // two latches for starting/stopping and lap times
    .res        (rst_n),
    .start_stop (ui_in[0]),
    .lap_time   (ui_in[1]),
    .counter_enable (counter_enable),
    .display_enable (display_enable)
  );

  assign uo_out[3] = counter_enable; // output the internal state
  assign uo_out[4] = display_enable;

  counter_chain counter_chain1 ( // a chain of 6 counters that count from 00:00:00 to 59:59:99
    .clk (dividedClock),
    .ena (counter_enable),
    .res (reset_either),
    .min_X0 (min_X0),
    .min_0X (min_0X),
    .sec_X0 (sec_X0),
    .sec_0X (sec_0X),
    .ces_X0 (ces_X0),
    .ces_0X (ces_0X)
  );

  SPI_wrapper SPI_wrapper1 (
    .clk (clk),
    .clk_div(dividedClock),
    .res (rst_n),
    .ena (display_enable),
    .min_X0 (min_X0),
    .min_0X (min_0X),
    .sec_X0 (sec_X0),
    .sec_0X (sec_0X),
    .ces_X0 (ces_X0),
    .ces_0X (ces_0X),
    .Mosi    (uo_out[0]), // MOSI on out 0
    .Cs      (uo_out[1]), //  CS  on out 1
    .clk_SPI (uo_out[2])  //  CLK on out 3
  );

endmodule // tt_um_faramire_stopwatch

module clockDivider (
    input wire clk_in, // input clock 1 MHz
    input wire res,    // async reset, active low
    output reg clk_out // output clock 100 Hz
 );

    reg[13:0] counter;
    parameter div     = 5000; // 1 MHz / 10'000 = 100 Hz, 50% duty cycle => 1/2 of that


    always @(posedge clk_in or negedge res) begin
        if (!res) begin     // async reset
            counter <= 14'b0;
            clk_out <= 1'b0;
        end else if (counter < (div-1)) begin    // count up
            counter <= counter + 1;
        end else begin                  // reset counter and invert output
            counter <= 14'b0;
            clk_out <= ~clk_out; 
        end
    end

endmodule //clockDivider

module controller (
    input  wire res,            // reset, active low
    input  wire start_stop,     // impulse toggles counter_enable
    input  wire lap_time,       // impulse toggles display_enable
    output reg  counter_enable, // 
    output reg  display_enable  //
 );
  
    always @(posedge start_stop or negedge res) begin
        if (!res)
            counter_enable <= 1'b0;
        else
            counter_enable <= ~counter_enable;
    end
  
    always @(posedge lap_time or negedge res) begin
        if (!res)
            display_enable <= 1'b1;
        else
            display_enable <= ~display_enable;
    end
  
endmodule // controller

module counter6 (
    input  wire      clk, // clock
    input  wire      ena, // enable
    input  wire      res, // reset, active low
    output reg       max, // high when max value (6) reached
    output reg [2:0] cnt  // 3 bit counter output
 );

    parameter max_count = 6;

    always @(posedge clk or negedge res) begin
        if (!res) begin
            cnt <= 3'b0;
            max <= 1'b0;
        end else if (ena) begin
            if (cnt < (max_count-1)) begin
                cnt <= cnt + 1;
            end else begin
                cnt <= 3'b0;
            end

          if (cnt == max_count-2) begin
            	max <= 1'b1;
            end else begin
                max <= 1'b0;
            end
        end
    end

endmodule // counter6

module counter10 (
    input  wire      clk, // clock
    input  wire      ena, // enable
    input  wire      res, // reset, active low
    output reg       max, // high when max value (10) reached
    output reg [3:0] cnt  // 3 bit counter output
 );

    parameter max_count = 10;

    always @(posedge clk or negedge res) begin
        if (!res) begin
            cnt <= 4'b0;
            max <= 1'b0;
        end else if (ena) begin
            if (cnt < (max_count-1)) begin
                cnt <= cnt + 1;
            end else begin
                cnt <= 4'b0;
            end

          if (cnt == max_count-2) begin
            	max <= 1'b1;
            end else begin
                max <= 1'b0;
            end
        end
    end

endmodule // counter10

module counter_chain (
    input wire clk,
    input wire ena,
    input wire res,
    // the X denotes which digit the counter drives
    output wire [3:0] ces_0X, // centiseconds (100th)
    output wire [3:0] ces_X0,
    output wire [3:0] sec_0X, // seconds
    output wire [2:0] sec_X0,
    output wire [3:0] min_0X, // minutes
    output wire [2:0] min_X0
 );

    wire ces_X0_ena;
    wire sec_0X_ena;
    wire sec_X0_ena;
    wire min_0X_ena;
    wire min_X0_ena;

    counter10 inst_ces_0X ( // counts first digit centiseconds
        .clk (clk), // clock in
        .ena (ena), // enable
        .res (res),  // reset
        .max (ces_X0_ena), // reached max value, used as enable for the next counter
        .cnt (ces_0X) // output value
    );

    counter10 inst_ces_X0 ( // counts second digit centiseconds
        .clk (clk),
        .ena (ena & ces_X0_ena),
        .res (res),
        .max (sec_0X_ena),
        .cnt (ces_X0)
    );

    counter10 inst_sec_0X ( // counts first digit seconds
        .clk (clk),
        .ena (ena & ces_X0_ena & sec_0X_ena),
        .res (res),
        .max (sec_X0_ena),
        .cnt (sec_0X)
    );

    counter6 inst_sec_X0 ( // counts second digit seconds
        .clk (clk),
        .ena (ena & ces_X0_ena & sec_0X_ena & sec_X0_ena),
        .res (res),
        .max (min_0X_ena),
        .cnt (sec_X0)
    );

    counter10 inst_min_0X ( // counts single digit minutes
        .clk (clk),
        .ena (ena & ces_X0_ena & sec_0X_ena & sec_X0_ena & min_0X_ena),
        .res (res),
        .max (min_X0_ena),
        .cnt (min_0X)
    );

    counter6 inst_min_X0 ( // counts second digit minutes
        .clk (clk),
        .ena (ena & ces_X0_ena & sec_0X_ena & sec_X0_ena & min_0X_ena & min_X0_ena),
        .res (res),
        .max (),
        .cnt (min_X0)
    );

endmodule // counter_chain

module SPI_wrapper (
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

    output wire Mosi,
    output wire Cs,
    output wire clk_SPI
);
    
    // FSM
    reg [1:0] state;
    localparam SETUP = 2'b00;
    localparam IDLE = 2'b01;
    localparam TRANSFER = 2'b10;
    localparam WAIT = 2'b11;

    reg word_pos; // 0 -> MSBy, 1 -> LSBy
    reg [7:0] byte_out;
    reg send_byte;
    reg [2:0] digit_count;
    wire next_byte;

    always @(posedge clk or negedge res) begin  // controlling FSM
        if (!res) begin // active low reset
            state <= SETUP;
        end
        case(state)

            SETUP: begin // send a setup packet enabling BCD
                if (next_byte & res) begin
                    if (word_pos == 1'b0) begin
                        byte_out <= 8'b00001001; // address = decode mode
                        send_byte <= 1'b1;
                        word_pos <= 1'b1;
                    end
                    else begin
                        byte_out <= 8'b11111111; // data = BCD for all
                        send_byte <= 1'b1;
                        word_pos <= 1'b0;
                        state <= IDLE;
                    end
                end else begin
                    send_byte <= 1'b0;
                end
            end

            IDLE: begin
                if (clk_div & ena) begin // wait for the 100Hz clock to get high
                    digit_count <= 3'b000;
                    state <= TRANSFER;
                end
            end

            TRANSFER: begin
                if (next_byte) begin // TX ready
                    if (word_pos == 1'b0) begin // address byte
                        case(digit_count)

                            3'b000: begin // ces_0X
                                byte_out <= 8'b00000001;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            3'b001: begin // ces_X0
                                byte_out <= 8'b00000010;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            3'b010: begin // sec_0X
                                byte_out <= 8'b00000011;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            3'b011: begin // sec_X0
                                byte_out <= 8'b00000100;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            3'b100: begin // min_0X
                                byte_out <= 8'b00000101;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            3'b101: begin // min_X0
                                byte_out <= 8'b00000110;
                                send_byte <= 1'b1;
                                word_pos <= 1'b1;
                            end

                            default:digit_count <= 3'b000;
                        endcase
                    end

                    else if (word_pos == 1'b1) begin // data byte

                        case(digit_count)

                            3'b000: begin // ces_0X
                                byte_out <= 8'b00000000 | ces_0X;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                digit_count <= 3'b001;
                            end

                            3'b001: begin // ces_X0
                                byte_out <= 8'b00000000 | ces_X0;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                digit_count <= 3'b010;
                            end

                            3'b010: begin // sec_0X
                                byte_out <= 8'b00000000 | sec_0X;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                digit_count <= 3'b011;
                            end

                            3'b011: begin // sec_X0
                                byte_out <= 8'b00000000 | sec_X0;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                digit_count <= 3'b100;
                            end

                            3'b100: begin // min_0X
                                byte_out <= 8'b00000000 | min_0X;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                digit_count <= 3'b101;
                            end

                            3'b101: begin // min_X0
                                byte_out <= 8'b00000000 | min_X0;
                                send_byte <= 1'b1;
                                word_pos <= 1'b0;
                                state <= WAIT;
                            end

                            default:digit_count <= 3'b000;
                        endcase
                    end

                end else begin
                    send_byte <= 1'b0;
                end
            end

            WAIT: begin // wait for the 100 Hz clock to go low again
                if (!clk_div) begin
                    state <= IDLE;
                end
            end

            default:state <= SETUP;
        endcase    
    end

    SPI_Master_With_Single_CS SPI_Master1 (
        .i_Rst_L(res),
        .i_Clk(clk),

        .i_TX_Byte(byte_out),
        .i_TX_DV(send_byte),
        .o_TX_Ready(next_byte),

        .o_SPI_Clk(clk_SPI),
        .o_SPI_MOSI(Mosi),
        .o_SPI_CS_n(Cs)
    );

endmodule // SPI_wrapper

/*
 * Copyright (c) 2019 russell-merrick
 * SPDX-License-Identifier: MIT
 * https://github.com/nandland/spi-master
 */

///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              With single chip-select (AKA Slave Select) capability
//
//              Supports arbitrary length byte transfers.
// 
//              Instantiates a SPI Master and adds single CS.
//              If multiple CS signals are needed, will need to use different
//              module, OR multiplex the CS from this at a higher level.
//
// Note:        i_Clk must be at least 2x faster than i_SPI_Clk
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
//              MAX_BYTES_PER_CS - Set to the maximum number of bytes that
//              will be sent during a single CS-low pulse.
// 
//              CS_INACTIVE_CLKS - Sets the amount of time in clock cycles to
//              hold the state of Chip-Selct high (inactive) before next 
//              command is allowed on the line.  Useful if chip requires some
//              time when CS is high between trasnfers.
///////////////////////////////////////////////////////////////////////////////

module SPI_Master_With_Single_CS
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 2,
    parameter MAX_BYTES_PER_CS = 2,
    parameter CS_INACTIVE_CLKS = 2)
  (
   // Control/Data Signals,
   input        i_Rst_L,     // FPGA Reset
   input        i_Clk,       // FPGA Clock
   
   // TX (MOSI) Signals
   input [$clog2(MAX_BYTES_PER_CS+1)-1:0] i_TX_Count,  // # bytes per CS low
   input [7:0]  i_TX_Byte,       // Byte to transmit on MOSI
   input        i_TX_DV,         // Data Valid Pulse with i_TX_Byte
   output       o_TX_Ready,      // Transmit Ready for next byte
   
   // RX (MISO) Signals
   output reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] o_RX_Count,  // Index RX byte
   output       o_RX_DV,     // Data Valid pulse (1 clock cycle)
   output [7:0] o_RX_Byte,   // Byte received on MISO

   // SPI Interface
   output o_SPI_Clk,
   input  i_SPI_MISO,
   output o_SPI_MOSI,
   output o_SPI_CS_n
   );

  localparam IDLE        = 2'b00;
  localparam TRANSFER    = 2'b01;
  localparam CS_INACTIVE = 2'b10;

  reg [1:0] r_SM_CS;
  reg r_CS_n;
  reg [$clog2(CS_INACTIVE_CLKS)-1:0] r_CS_Inactive_Count;
  reg [$clog2(MAX_BYTES_PER_CS+1)-1:0] r_TX_Count;
  wire w_Master_Ready;

  // Instantiate Master
  SPI_Master 
    #(.SPI_MODE(SPI_MODE),
      .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)
      ) SPI_Master_Inst
   (
   // Control/Data Signals,
   .i_Rst_L(i_Rst_L),     // FPGA Reset
   .i_Clk(i_Clk),         // FPGA Clock
   
   // TX (MOSI) Signals
   .i_TX_Byte(i_TX_Byte),         // Byte to transmit
   .i_TX_DV(i_TX_DV),             // Data Valid Pulse 
   .o_TX_Ready(w_Master_Ready),   // Transmit Ready for Byte
   
   // RX (MISO) Signals
   .o_RX_DV(o_RX_DV),       // Data Valid pulse (1 clock cycle)
   .o_RX_Byte(o_RX_Byte),   // Byte received on MISO

   // SPI Interface
   .o_SPI_Clk(o_SPI_Clk),
   .i_SPI_MISO(i_SPI_MISO),
   .o_SPI_MOSI(o_SPI_MOSI)
   );


  // Purpose: Control CS line using State Machine
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_SM_CS <= IDLE;
      r_CS_n  <= 1'b1;   // Resets to high
      r_TX_Count <= 0;
      r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
    end
    else
    begin

      case (r_SM_CS)      
      IDLE:
        begin
          if (r_CS_n & i_TX_DV) // Start of transmission
          begin
            r_TX_Count <= i_TX_Count - 1'b1; // Register TX Count
            r_CS_n     <= 1'b0;       // Drive CS low
            r_SM_CS    <= TRANSFER;   // Transfer bytes
          end
        end

      TRANSFER:
        begin
          // Wait until SPI is done transferring do next thing
          if (w_Master_Ready)
          begin
            if (r_TX_Count > 0)
            begin
              if (i_TX_DV)
              begin
                r_TX_Count <= r_TX_Count - 1'b1;
              end
            end
            else
            begin
              r_CS_n  <= 1'b1; // we done, so set CS high
              r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
              r_SM_CS             <= CS_INACTIVE;
            end // else: !if(r_TX_Count > 0)
          end // if (w_Master_Ready)
        end // case: TRANSFER

      CS_INACTIVE:
        begin
          if (r_CS_Inactive_Count > 0)
          begin
            r_CS_Inactive_Count <= r_CS_Inactive_Count - 1'b1;
          end
          else
          begin
            r_SM_CS <= IDLE;
          end
        end

      default:
        begin
          r_CS_n  <= 1'b1; // we done, so set CS high
          r_SM_CS <= IDLE;
        end
      endcase // case (r_SM_CS)
    end
  end // always @ (posedge i_Clk or negedge i_Rst_L)


  // Purpose: Keep track of RX_Count
  always @(posedge i_Clk)
  begin
    begin
      if (r_CS_n)
      begin
        o_RX_Count <= 0;
      end
      else if (o_RX_DV)
      begin
        o_RX_Count <= o_RX_Count + 1'b1;
      end
    end
  end

  assign o_SPI_CS_n = r_CS_n;

  assign o_TX_Ready  = ((r_SM_CS == IDLE) | (r_SM_CS == TRANSFER && w_Master_Ready == 1'b1 && r_TX_Count > 0)) & ~i_TX_DV;

endmodule // SPI_Master_With_Single_CS

module SPI_Master
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 2)
  (
   // Control/Data Signals,
   input        i_Rst_L,     // FPGA Reset
   input        i_Clk,       // FPGA Clock
   
   // TX (MOSI) Signals
   input [7:0]  i_TX_Byte,        // Byte to transmit on MOSI
   input        i_TX_DV,          // Data Valid Pulse with i_TX_Byte
   output reg   o_TX_Ready,       // Transmit Ready for next byte
   
   // RX (MISO) Signals
   output reg       o_RX_DV,     // Data Valid pulse (1 clock cycle)
   output reg [7:0] o_RX_Byte,   // Byte received on MISO

   // SPI Interface
   output reg o_SPI_Clk,
   input      i_SPI_MISO,
   output reg o_SPI_MOSI
   );

  // SPI Interface (All Runs at SPI Clock Domain)
  wire w_CPOL;     // Clock polarity
  wire w_CPHA;     // Clock phase

  reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count;
  reg r_SPI_Clk;
  reg [4:0] r_SPI_Clk_Edges;
  reg r_Leading_Edge;
  reg r_Trailing_Edge;
  reg       r_TX_DV;
  reg [7:0] r_TX_Byte;

  reg [2:0] r_RX_Bit_Count;
  reg [2:0] r_TX_Bit_Count;

  // CPOL: Clock Polarity
  // CPOL=0 means clock idles at 0, leading edge is rising edge.
  // CPOL=1 means clock idles at 1, leading edge is falling edge.
  assign w_CPOL  = (SPI_MODE == 2) | (SPI_MODE == 3);

  // CPHA: Clock Phase
  // CPHA=0 means the "out" side changes the data on trailing edge of clock
  //              the "in" side captures data on leading edge of clock
  // CPHA=1 means the "out" side changes the data on leading edge of clock
  //              the "in" side captures data on the trailing edge of clock
  assign w_CPHA  = (SPI_MODE == 1) | (SPI_MODE == 3);



  // Purpose: Generate SPI Clock correct number of times when DV pulse comes
  always @(posedge i_Clk) // or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_TX_Ready      <= 1'b0;
      r_SPI_Clk_Edges <= 0;
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      r_SPI_Clk       <= w_CPOL; // assign default state to idle state
      r_SPI_Clk_Count <= 0;
    end
    else begin

      // Default assignments
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      
      if (i_TX_DV)
      begin
        o_TX_Ready      <= 1'b0;
        r_SPI_Clk_Edges <= 16;  // Total # edges in one byte ALWAYS 16
      end
      else if (r_SPI_Clk_Edges > 0)
      begin
        o_TX_Ready <= 1'b0;
        
        if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT*2-1)
        begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;
          r_Trailing_Edge <= 1'b1;
          r_SPI_Clk_Count <= 0;
          r_SPI_Clk       <= ~r_SPI_Clk;
        end
        else if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT-1)
        begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;
          r_Leading_Edge  <= 1'b1;
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;
          r_SPI_Clk       <= ~r_SPI_Clk;
        end
        else
        begin
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;
        end
      end  
      else
      begin
        o_TX_Ready <= 1'b1;
      end
      
      
    end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)


  // Purpose: Register i_TX_Byte when Data Valid is pulsed.
  // Keeps local storage of byte in case higher level module changes the data
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_TX_Byte <= 8'h00;
      r_TX_DV   <= 1'b0;
    end
    else
      begin
        r_TX_DV <= i_TX_DV; // 1 clock cycle delay
        if (i_TX_DV)
        begin
          r_TX_Byte <= i_TX_Byte;
        end
      end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)


  // Purpose: Generate MOSI data
  // Works with both CPHA=0 and CPHA=1
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_SPI_MOSI     <= 1'b0;
      r_TX_Bit_Count <= 3'b111; // send MSb first
    end
    else
    begin
      // If ready is high, reset bit counts to default
      if (o_TX_Ready)
      begin
        r_TX_Bit_Count <= 3'b111;
      end
      // Catch the case where we start transaction and CPHA = 0
      else if (r_TX_DV & ~w_CPHA)
      begin
        o_SPI_MOSI     <= r_TX_Byte[3'b111];
        r_TX_Bit_Count <= 3'b110;
      end
      else begin
        if (r_Leading_Edge & w_CPHA) begin
          r_TX_Bit_Count <= r_TX_Bit_Count - 1'b1;
          o_SPI_MOSI     <= r_TX_Byte[r_TX_Bit_Count];
        end
        else if (r_Trailing_Edge & ~w_CPHA) begin
          r_TX_Bit_Count <= r_TX_Bit_Count - 1'b1;
          o_SPI_MOSI     <= r_TX_Byte[r_TX_Bit_Count];
        end
      end
    end
  end


/*   // Purpose: Read in MISO data.
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_RX_Byte      <= 8'h00;
      o_RX_DV        <= 1'b0;
      r_RX_Bit_Count <= 3'b111;
    end
    else
    begin

      // Default Assignments
      o_RX_DV   <= 1'b0;

      if (o_TX_Ready) // Check if ready is high, if so reset bit count to default
      begin
        r_RX_Bit_Count <= 3'b111;
      end
      else if ((r_Leading_Edge & ~w_CPHA) | (r_Trailing_Edge & w_CPHA))
      begin
        o_RX_Byte[r_RX_Bit_Count] <= i_SPI_MISO;  // Sample data
        r_RX_Bit_Count            <= r_RX_Bit_Count - 1'b1;
        if (r_RX_Bit_Count == 3'b000)
        begin
          o_RX_DV   <= 1'b1;   // Byte done, pulse Data Valid
        end
      end
    end
  end */
  
  
  // Purpose: Add clock delay to signals for alignment.
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_SPI_Clk  <= w_CPOL;
    end
    else
      begin
        o_SPI_Clk <= r_SPI_Clk;
      end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)
  

endmodule // SPI_Master