module conv1d_datapath #(
    parameter DATA_WIDTH = 16,
    parameter IN_CHANNELS  = 1,
    parameter OUT_CHANNELS = 16,
    parameter KERNEL_SIZE  = 5,
    parameter STRIDE = 2,
    parameter PADDING = 2,
    parameter IN_LENGTH = 180,
    parameter OUT_LENGTH = 90,
    parameter WEIGHT_FILE = "conv1_weight.mem",
    parameter BIAS_FILE = "conv1_bias.mem",
    parameter RELU_EN = 1
)(
    input  logic clk,

    // pipelined control inputs 

    input logic load_bias,
    input  logic mac_en,
    input  logic mac_en_d1,
    input  logic write_en,

    // counters
    input  logic [((OUT_LENGTH > 1) ? $clog2(OUT_LENGTH) : 1)-1:0] pos_cnt,
    input  logic [((OUT_CHANNELS > 1) ? $clog2(OUT_CHANNELS): 1)-1:0] o_cnt,
    input  logic [((IN_CHANNELS > 1) ? $clog2(IN_CHANNELS) : 1)-1:0] ch_cnt,
    input  logic [((KERNEL_SIZE > 1) ? $clog2(KERNEL_SIZE) : 1)-1:0] tap_cnt,

    //feature BRAM read interface (1-cycle registered latency)
    output logic feat_rd_en,
    output logic [$clog2(IN_CHANNELS * IN_LENGTH)-1:0] feat_rd_addr,
    input  logic signed [DATA_WIDTH-1:0] feat_rd_data,

    // output BRAM write interface 
    output logic out_wr_en,
    output logic [$clog2(OUT_CHANNELS * OUT_LENGTH)-1:0] out_wr_addr,
    output logic signed [DATA_WIDTH-1:0]out_wr_data
);

// Bit-width localparams
localparam IN_ADDR_W  = $clog2(IN_CHANNELS  * IN_LENGTH);
localparam OUT_ADDR_W = $clog2(OUT_CHANNELS * OUT_LENGTH);
localparam W_DEPTH    = OUT_CHANNELS * IN_CHANNELS * KERNEL_SIZE;
localparam W_ADDR_W   = $clog2(W_DEPTH > 1 ? W_DEPTH : 2);
localparam B_ADDR_W   = $clog2(OUT_CHANNELS > 1 ? OUT_CHANNELS : 2);
localparam ACC_WIDTH  = 2*DATA_WIDTH + $clog2(IN_CHANNELS * KERNEL_SIZE);
localparam ADDR_WIDTH = $clog2(IN_LENGTH + PADDING + KERNEL_SIZE) + 1;
localparam MUL_WIDTH  = 2 * DATA_WIDTH;


(* rom_style = "block" *) logic signed [DATA_WIDTH-1:0] weight_mem [W_DEPTH];
initial $readmemh(WEIGHT_FILE, weight_mem);

logic [W_ADDR_W-1:0] w_rd_addr_comb;
logic [W_ADDR_W-1:0] w_rd_addr_reg;
logic signed [DATA_WIDTH-1:0] w_rd_data;

always_comb
    w_rd_addr_comb = W_ADDR_W'( o_cnt * (IN_CHANNELS * KERNEL_SIZE) + ch_cnt * KERNEL_SIZE + tap_cnt);

// Stage 1: register address FF — critical path fix
always_ff @(posedge clk)
    w_rd_addr_reg <= w_rd_addr_comb;

// Stage 2: BRAM read (1-cycle latency from registered address)
always_ff @(posedge clk)
    w_rd_data <= weight_mem[w_rd_addr_reg];

// Bias BRAM 
(* rom_style = "block" *) logic signed [DATA_WIDTH-1:0] bias_mem [OUT_CHANNELS];
initial $readmemh(BIAS_FILE, bias_mem);

logic [B_ADDR_W-1:0] b_rd_addr;
logic signed [DATA_WIDTH-1:0] b_rd_data;

always_comb
    b_rd_addr = B_ADDR_W'(o_cnt);

always_ff @(posedge clk)
    b_rd_data <= bias_mem[b_rd_addr];

// Feature BRAM address generation

logic signed [ADDR_WIDTH-1:0] feat_addr_raw;
logic [IN_ADDR_W-1:0] feat_pos;

always_comb begin
    feat_addr_raw = $signed(ADDR_WIDTH'({1'b0, pos_cnt})) * STRIDE + $signed(ADDR_WIDTH'({1'b0, tap_cnt})) - $signed(ADDR_WIDTH'(PADDING));

    feat_pos = IN_ADDR_W'(feat_addr_raw);

    if (feat_addr_raw < 0 || feat_addr_raw >= IN_LENGTH) begin
        feat_rd_en = 1'b0;
        feat_rd_addr = '0;
    end
    else begin
        feat_rd_en = 1'b1;
        feat_rd_addr = IN_ADDR_W'(ch_cnt * IN_LENGTH) + feat_pos;
    end
end

// Cycle N+1: feat_rd_data valid, feat_was_valid valid
logic feat_was_valid;
always_ff @(posedge clk)
    feat_was_valid <= feat_rd_en;

// Cycle N+2: delay 1 more cycle to align with w_rd_data
logic signed [DATA_WIDTH-1:0] feat_rd_data_d1;
logic feat_was_valid_d1;
always_ff @(posedge clk) begin
    feat_rd_data_d1 <= feat_rd_data;
    feat_was_valid_d1 <= feat_was_valid;
end

// Sample mux — uses delayed versions aligned with w_rd_data
logic signed [DATA_WIDTH-1:0] sample;
always_comb
    sample = feat_was_valid_d1 ? feat_rd_data_d1 : '0;

// Stage 1 of MAC: register multiply result

logic signed [MUL_WIDTH-1:0] mul_reg;

always_ff @(posedge clk) begin
    if (mac_en)
        mul_reg <= $signed(sample) * $signed(w_rd_data);
    else
        mul_reg <= '0;
end

// Single accumulator

logic signed [ACC_WIDTH-1:0] acc;

always_ff @(posedge clk) begin
    if (load_bias)
        acc <= ACC_WIDTH'({{8{b_rd_data[DATA_WIDTH-1]}}, b_rd_data, 8'b0});
    else if (mac_en_d1)
        acc <= acc + ACC_WIDTH'(mul_reg);
end

// Output write 

logic signed [DATA_WIDTH-1:0] relu_result;
always_comb
    relu_result = (RELU_EN && acc[DATA_WIDTH-1+8]) ? '0 : acc[DATA_WIDTH-1+8 : 8];

assign out_wr_en = write_en;
assign out_wr_addr = OUT_ADDR_W'(o_cnt * OUT_LENGTH + pos_cnt);
assign out_wr_data = relu_result;

endmodule
