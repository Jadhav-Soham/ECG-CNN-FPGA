module gap #(
    parameter DATA_WIDTH  = 16,
    parameter IN_CHANNELS = 64,
    parameter IN_LENGTH   = 23
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    // Feature map from Conv3 output
    input  logic signed [DATA_WIDTH-1:0] gap_in  [IN_CHANNELS][IN_LENGTH],

    // One value per channel after averaging
    output logic signed [DATA_WIDTH-1:0] gap_out [IN_CHANNELS][1]
);

localparam ACC_WIDTH = DATA_WIDTH + $clog2(IN_LENGTH);

// GAP_SHIFT = floor(log2(IN_LENGTH)) — approximate division
// e.g. IN_LENGTH=23 → shift by 4 (divide by 16) (30 percent error)
// Replace with exact division after quantisation is finalised
localparam GAP_SHIFT = $clog2(IN_LENGTH);

logic signed [ACC_WIDTH-1:0] acc [IN_CHANNELS];

// Position counter — walks across IN_LENGTH positions
logic [$clog2(IN_LENGTH)-1:0] pos;

// FSM
localparam S_IDLE  = 0,
           S_CLEAR = 1,
           S_RUN   = 2,
           S_WRITE = 3,
           S_DONE  = 4;

logic [2:0] state;

always_ff @(posedge clk) begin
    if(rst) begin
        state <= S_IDLE;
        pos   <= 0;
        done  <= 0;
    end
    else begin
        done <= 0; 

        case(state)

        S_IDLE: begin
            if(start) begin
                pos   <= 0;
                state <= S_CLEAR;
            end
        end

        // Clear all accumulators in one cycle
        S_CLEAR: begin
            for(int ch=0; ch<IN_CHANNELS; ch++)
                acc[ch] <= 0;
            state <= S_RUN;
        end

        // Accumulate one position per cycle across all channels in parallel
        S_RUN: begin
            for(int ch=0; ch<IN_CHANNELS; ch++)
                acc[ch] <= acc[ch] + gap_in[ch][pos];

            if(pos < IN_LENGTH-1) begin
                pos   <= pos + 1;
                state <= S_RUN;
            end
            else begin
                state <= S_WRITE;
            end
        end

        // Shift-divide and latch into gap_out
        S_WRITE: begin
            for(int ch=0; ch<IN_CHANNELS; ch++)
                gap_out[ch][0] <= acc[ch] >> GAP_SHIFT;
            state <= S_DONE;
        end

        S_DONE: begin
            done  <= 1;
            state <= S_IDLE;
        end

        endcase
    end
end

endmodule
