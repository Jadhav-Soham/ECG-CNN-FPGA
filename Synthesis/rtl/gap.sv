module gap #(
    parameter DATA_WIDTH  = 16,
    parameter IN_CHANNELS = 64,
    parameter IN_LENGTH   = 23
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    //feature BRAM read port (1-cycle registered latency)
    output logic feat_rd_en,
    output logic [$clog2(IN_CHANNELS * IN_LENGTH)-1:0] feat_rd_addr,
    input  logic signed [DATA_WIDTH-1:0] feat_rd_data,

    // GAP output: one value per channel
    output logic signed [DATA_WIDTH-1:0] gap_out [IN_CHANNELS]
);

localparam ACC_WIDTH = DATA_WIDTH + $clog2(IN_LENGTH);
localparam GAP_SHIFT = $clog2(IN_LENGTH) - 1;

logic signed [ACC_WIDTH-1:0] acc [IN_CHANNELS];

// Position counter
logic [$clog2(IN_LENGTH)-1:0] pos;

localparam CH_BITS = (IN_CHANNELS > 1) ? $clog2(IN_CHANNELS) : 1;
logic [CH_BITS-1:0] ch;

// FSM
localparam S_IDLE  = 3'd0,
           S_CLEAR = 3'd1,
           S_ADDR  = 3'd2,   // present address to BRAM
           S_ACC   = 3'd3,   // data valid — accumulate
           S_WRITE = 3'd4,
           S_DONE  = 3'd5;

logic [2:0] state;


// BRAM read address (driven 1 cycle before data needed)

always_comb begin
    feat_rd_en   = (state == S_ADDR);
    feat_rd_addr = ch * IN_LENGTH + pos;
end

// Latch channel index 
logic [CH_BITS-1:0] ch_d1;
always_ff @(posedge clk)
    ch_d1 <= ch;

// FSM + accumulator

always_ff @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE;
        pos <= '0;
        ch <= '0;
        done <= 1'b0;
    end
    else begin
        done <= 1'b0;

        case (state)

        S_IDLE: begin
            if (start) begin
                pos <= '0;
                ch <= '0;
                state <= S_CLEAR;
            end
        end

        // Clear all accumulators in one cycle
        S_CLEAR: begin
            for (int i = 0; i < IN_CHANNELS; i++)
                acc[i] <= '0;
            ch    <= '0;
            state <= S_ADDR;
        end

        // Present (ch, pos) address to BRAM 
        S_ADDR: begin
            state <= S_ACC;
        end

        // BRAM data is now valid — accumulate into acc[ch_d1]
        S_ACC: begin
            acc[ch_d1] <= acc[ch_d1] + feat_rd_data;

            if (ch < IN_CHANNELS - 1) begin
                ch <= ch + 1'b1;
                state <= S_ADDR;        // next channel, same pos
            end
            else begin
                ch <= '0;
                if (pos < IN_LENGTH - 1) begin
                    pos   <= pos + 1'b1;
                    state <= S_ADDR; // next position, ch wraps to 0
                end
                else
                    state <= S_WRITE;
            end
        end

        // Shift-divide and latch into gap_out registers
        S_WRITE: begin
            for (int i = 0; i < IN_CHANNELS; i++)
                gap_out[i] <= acc[i] >>> GAP_SHIFT;
            state <= S_DONE;
        end

        S_DONE: begin
            done  <= 1'b1;
            state <= S_IDLE;
        end

        default: state <= S_IDLE;

        endcase
    end
end

endmodule
