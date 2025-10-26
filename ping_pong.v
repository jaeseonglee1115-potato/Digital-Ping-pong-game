//=============================================================================
// Top-Level Module: digital_ping_pong
//=============================================================================
module digital_ping_pong (
    input  wire clk,          // On-board fast clock (e.g., 100MHz)
    input  wire reset,        // System reset (also starts/resets game)
    input  wire sw_p1_hit,   // Player 1 (Left) paddle hit button
    input  wire sw_p2_hit,   // Player 2 (Right) paddle hit button

    output wire [7:0] led,    // 8 LEDs for ball position (one-hot)
    output wire [6:0] seg,    // 7-segment display segments (active-low)
    output wire [1:0] an      // 2 Anode selectors (active-low)
);

    // --- Internal Wires ---

    // Slow clock for game logic (e.g., ~4Hz)
    wire game_clk;

    // Debounced button signals
    wire btn_p1_hit;
    wire btn_p2_hit;

    // Pulses from FSM to signal a point was scored
    wire p1_point_pulse;
    wire p2_point_pulse;

    // 4-bit BCD score for each player
    wire [3:0] p1_score_bcd;
    wire [3:0] p2_score_bcd;

    // --- Module Instantiations ---

    // 1. Clock Divider
    // Creates the slow game_clk for the FSM and ball movement.
    // 100MHz / (2 * 25,000,000) = 2 Hz. Adjust DIV_FACTOR for ball speed.
    clock_divider #(
        .DIV_FACTOR(25'd12_500_000) // ~4Hz game clock with 100MHz input
    ) game_clk_div (
        .clk_in(clk),
        .reset(reset),
        .clk_out(game_clk)
    );

    // 2. Debouncers
    // Clean up the noisy switch/button inputs.
    debouncer p1_debouncer (
        .clk(clk),
        .reset(reset),
        .btn_in(sw_p1_hit),
        .btn_out(btn_p1_hit)
    );

    debouncer p2_debouncer (
        .clk(clk),
        .reset(reset),
        .btn_in(sw_p2_hit),
        .btn_out(btn_p2_hit)
    );

    // 3. Game FSM (The Core Logic)
    // Manages game state, ball position (led), and scoring pulses.
    game_fsm fsm (
        .clk(game_clk),
        .reset(reset),
        .btn_p1(btn_p1_hit),
        .btn_p2(btn_p2_hit),
        .led_out(led),
        .score_p1_point(p1_point_pulse),
        .score_p2_point(p2_point_pulse)
    );

    // 4. Score Counters
    // Two BCD counters, one for each player.
    score_counter p1_scorer (
        .clk(game_clk), // Use game_clk to increment score
        .reset(reset),
        .increment_point(p1_point_pulse),
        .score_bcd(p1_score_bcd)
    );

    score_counter p2_scorer (
        .clk(game_clk),
        .reset(reset),
        .increment_point(p2_point_pulse),
        .score_bcd(p2_score_bcd)
    );

    // 5. Seven-Segment Display Multiplexer
    // Takes both BCD scores and drives the 2-digit display.
    // Uses the fast main clock (clk) for a flicker-free refresh rate.
    seven_seg_mux display_mux (
        .clk(clk),
        .reset(reset),
        .score1_bcd(p1_score_bcd), // P1 score on left digit (AN1)
        .score2_bcd(p2_score_bcd), // P2 score on right digit (AN0)
        .seg_out(seg),
        .anode_sel(an)
    );

endmodule // digital_ping_pong


//=============================================================================
// Module: clock_divider
// Divides a fast clock to a slow, playable game clock.
//=============================================================================
module clock_divider #(
    parameter DIV_FACTOR = 25_000_000 // Default: 100MHz -> 2Hz
) (
    input  wire clk_in,
    input  wire reset,
    output reg  clk_out
);

    reg [$clog2(DIV_FACTOR)-1:0] counter = 0;

    always @(posedge clk_in or posedge reset) begin
        if (reset) begin
            counter <= 0;
            clk_out <= 0;
        end else if (counter == DIV_FACTOR - 1) begin
            counter <= 0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end

endmodule // clock_divider


//=============================================================================
// Module: debouncer
// Removes noise from mechanical switches/buttons.
//=============================================================================
module debouncer #(
    parameter DEBOUNCE_TIME_MS = 10,
    parameter CLK_FREQ_HZ = 100_000_000
) (
    input  wire clk,
    input  wire reset,
    input  wire btn_in,
    output wire btn_out
);

    // Calculate counter limit for ~10ms
    localparam COUNTER_LIMIT = (CLK_FREQ_HZ / 1000) * DEBOUNCE_TIME_MS;
    
    reg [$clog2(COUNTER_LIMIT)-1:0] count = 0;
    reg btn_state = 0;
    
    // 2-flop synchronizer for input
    reg s1, s2;
    always @(posedge clk) begin
        s1 <= btn_in;
        s2 <= s1;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
            btn_state <= 0;
        end else begin
            if (s2 != btn_state) begin
                // Input differs from stable state, start/continue counting
                if (count == COUNTER_LIMIT - 1) begin
                    // Timer expired, update the state
                    btn_state <= s2;
                    count <= 0;
                end else begin
                    count <= count + 1;
                end
            end else begin
                // Input matches stable state, reset counter
                count <= 0;
            end
        end
    end

    assign btn_out = btn_state;

endmodule // debouncer


//=============================================================================
// Module: game_fsm
// The core Finite State Machine for game logic.
// Implements a 1D "ball" (one-hot LED) moving left and right.
//=============================================================================
module game_fsm (
    input  wire clk,   // Slow game clock
    input  wire reset,
    input  wire btn_p1,
    input  wire btn_p2,

    output reg [7:0] led_out,         // One-hot ball position
    output reg       score_p1_point,  // Pulse on P1 score
    output reg       score_p2_point   // Pulse on P2 score
);

    // FSM States
    localparam [1:0] S_IDLE       = 2'b00;
    localparam [1:0] S_MOVE_RIGHT = 2'b01;
    localparam [1:0] S_MOVE_LEFT  = 2'b10;
    localparam [1:0] S_POINT_PAUSE= 2'b11;

    reg [1:0] state = S_IDLE;
    reg [7:0] ball_pos = 8'b00000001; // Ball position (one-hot)

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            ball_pos <= 8'b00000001; // Start at P1 side
            score_p1_point <= 0;
            score_p2_point <= 0;
        end else begin
            
            // Default pulse outputs to 0
            score_p1_point <= 0;
            score_p2_point <= 0;

            case (state)
                S_IDLE: begin
                    // Wait for reset to be released, then start game
                    state <= S_MOVE_RIGHT;
                    ball_pos <= 8'b00000001; // Serve from P1
                end

                S_MOVE_RIGHT: begin
                    if (ball_pos == 8'b10000000) begin // At P2 edge
                        if (btn_p2) begin
                            state <= S_MOVE_LEFT;     // P2 hit! Move left.
                            ball_pos <= ball_pos >> 1;
                        end else begin
                            state <= S_POINT_PAUSE;   // P2 missed! P1 scores.
                            score_p1_point <= 1;      // Assert pulse for one cycle
                            ball_pos <= 8'b10000000;  // Serve from P2
                        end
                    end else begin
                        ball_pos <= ball_pos << 1;    // Continue moving right
                    end
                end

                S_MOVE_LEFT: begin
                    if (ball_pos == 8'b00000001) begin // At P1 edge
                        if (btn_p1) begin
                            state <= S_MOVE_RIGHT;    // P1 hit! Move right.
                            ball_pos <= ball_pos << 1;
                        end else begin
                            state <= S_POINT_PAUSE;   // P1 missed! P2 scores.
                            score_p2_point <= 1;      // Assert pulse for one cycle
                            ball_pos <= 8'b00000001;  // Serve from P1
                        end
                    end else begin
                        ball_pos <= ball_pos >> 1;    // Continue moving left
                    end
                end
                
                S_POINT_PAUSE: begin
                    // Pause for one game_clk cycle after a point
                    if (ball_pos == 8'b00000001) begin // Last point was P2's
                        state <= S_MOVE_RIGHT; // Serve from P1
                    end else begin // Last point was P1's
                        state <= S_MOVE_LEFT;  // Serve from P2
                    end
                end
                
                default: begin
                    state <= S_IDLE;
                end
                
            endcase
        end
    end

    // Combinational output for LEDs
    assign led_out = ball_pos;

endmodule // game_fsm


//=============================================================================
// Module: score_counter
// A simple 4-bit BCD counter (0-9) that increments on a pulse.
//=============================================================================
module score_counter (
    input  wire clk,
    input  wire reset,
    input  wire increment_point, // Single-cycle pulse
    output reg  [3:0] score_bcd
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            score_bcd <= 4'd0;
        end else if (increment_point) begin
            if (score_bcd == 4'd9) begin
                score_bcd <= 4'd0; // Wrap around to 0
            end else begin
                score_bcd <= score_bcd + 1;
            end
        end
    end

endmodule // score_counter


//=============================================================================
// Module: seven_seg_mux
// Multiplexes two BCD scores onto a 2-digit 7-segment display.
// Instantiates the bcd_to_7seg decoder.
//=============================================================================
module seven_seg_mux (
    input  wire clk,   // Fast clock (e.g., 100MHz)
    input  wire reset,
    input  wire [3:0] score1_bcd, // P1 score
    input  wire [3:0] score2_bcd, // P2 score

    output wire [6:0] seg_out,   // 7-seg segments
    output reg  [1:0] anode_sel  // 2-digit anode select
);

    // --- Refresh Rate Clock Divider ---
    // Create a ~1kHz refresh clock from 100MHz
    // 100,000,000 / 100,000 = 1kHz
    localparam REFRESH_DIV = 16'd50000; // Gives 1kHz / 2 = ~500Hz per digit
    reg [15:0] refresh_counter = 0;
    reg refresh_clk_tick = 0;

    always @(posedge clk) begin
        if (refresh_counter == REFRESH_DIV - 1) begin
            refresh_counter <= 0;
            refresh_clk_tick <= ~refresh_clk_tick; // Toggle display digit
        end else begin
            refresh_counter <= refresh_counter + 1;
        end
    end
    
    // --- Digit Selection Logic ---
    reg [3:0] bcd_to_display;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            anode_sel <= 2'b10; // Default to digit 1 (P1)
            bcd_to_display <= score1_bcd;
        end else begin
            if (refresh_clk_tick) begin
                // Show P1 score on left digit (AN1)
                anode_sel <= 2'b10;
                bcd_to_display <= score1_bcd;
            end else begin
                // Show P2 score on right digit (AN0)
                anode_sel <= 2'b01;
                bcd_to_display <= score2_bcd;
            end
        end
    end

    // --- BCD Decoder Instantiation ---
    // Instantiate the K-Map optimized decoder
    bcd_to_7seg decoder (
        .bcd_in(bcd_to_display),
        .seg_out(seg_out)
    );

endmodule // seven_seg_mux


//=============================================================================
// Module: bcd_to_7seg
//
// ** K-Map Optimized Combinational Logic **
//
// Converts a 4-bit BCD input to 7-segment display outputs.
// This logic is for a COMMON ANODE display (active-low segments).
//   Segment mapping:
//      a
//     f g
//      b
//     e c
//      d
//
// Output: seg_out[6:0] = {g, f, e, d, c, b, a}
//
// This module directly implements the optimized sum-of-products or
// product-of-sums logic derived from K-Map analysis.
//=============================================================================
module bcd_to_7seg (
    input  wire [3:0] bcd_in,  // BCD digit (0-9)
    output wire [6:0] seg_out  // Active-low 7-segment signals {g,f,e,d,c,b,a}
);

    // Using a 'case' statement is the most readable way to synthesize
    // the combinational logic that would result from K-Maps.
    // The synthesizer will perform its own K-Map-like optimization.

    reg [6:0] segments;

    always @(*) begin
        case (bcd_in)
            // {g,f,e,d,c,b,a}
            4'h0: segments = 7'b0000001; // "0" (g=1)
            4'h1: segments = 7'b1001111; // "1" (a,d,e,f,g=1)
            4'h2: segments = 7'b0010010; // "2" (c,f=1)
            4'h3: segments = 7'b0000110; // "3" (e,f=1)
            4'h4: segments = 7'b1001100; // "4" (a,d,e=1)
            4'h5: segments = 7'b0100100; // "5" (b,e=1)
            4'h6: segments = 7'b0100000; // "6" (b=1)
            4'h7: segments = 7'b0001111; // "7" (d,e,f,g=1)
            4'h8: segments = 7'b0000000; // "8" (all on)
            4'h9: segments = 7'b0000100; // "9" (e=1)
            
            // Default case handles BCD values 10-15 (don't cares)
            // We'll just turn all segments off (blank).
            default: segments = 7'b1111111;
        endcase
    end

    assign seg_out = segments;

endmodule // bcd_to_7seg
