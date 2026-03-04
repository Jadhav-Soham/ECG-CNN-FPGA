module fc #(
    parameter DATA_WIDTH  = 16,
    parameter IN_FEATURES = 64,
    parameter OUT_CLASSES = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    input  logic signed [DATA_WIDTH-1:0] fc_in  [IN_FEATURES],
    output logic signed [DATA_WIDTH-1:0] fc_out [OUT_CLASSES]
);

// Accumulator width: product of two DATA_WIDTH values + enough bits
// for IN_FEATURES accumulations
localparam ACC_WIDTH = 2*DATA_WIDTH + $clog2(IN_FEATURES);

// Weights and biases — internal, loaded via $readmemh in simulation
// On FPGA: initialise BRAM with .coe file
logic signed [DATA_WIDTH-1:0] weight [OUT_CLASSES][IN_FEATURES];
logic signed [DATA_WIDTH-1:0] bias   [OUT_CLASSES];

initial begin
    $readmemh("fc_weight.hex", weight);
    $readmemh("fc_bias.hex",   bias);
end

logic signed [ACC_WIDTH-1:0] acc [OUT_CLASSES];

// Input feature counter
logic [$clog2(IN_FEATURES)-1:0] pos;

// FSM
localparam S_IDLE      = 0,
           S_LOAD_BIAS = 1,
           S_RUN       = 2,
           S_WRITE     = 3,
           S_DONE      = 4;

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
                state <= S_LOAD_BIAS;
            end
        end

        // Preload accumulators with bias values
        S_LOAD_BIAS: begin
            for(int c=0; c<OUT_CLASSES; c++)
                acc[c] <= bias[c];
            state <= S_RUN;
        end

        // One MAC per cycle, all output classes in parallel
        S_RUN: begin
            for(int c=0; c<OUT_CLASSES; c++)
                acc[c] <= acc[c] + (fc_in[pos] * weight[c][pos]);

            if(pos < IN_FEATURES-1) begin
                pos   <= pos + 1;
            end
            else begin
                state <= S_WRITE;
            end
        end

        // Truncate accumulator to output width and latch
        S_WRITE: begin
            for(int c=0; c<OUT_CLASSES; c++)
                fc_out[c] <= acc[c][DATA_WIDTH-1:0];
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
