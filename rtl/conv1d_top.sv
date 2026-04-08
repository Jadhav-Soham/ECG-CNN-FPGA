module conv1d_top #(
    parameter DATA_WIDTH = 16,
    parameter IN_CHANNELS = 1,
    parameter OUT_CHANNELS = 16,
    parameter KERNEL_SIZE = 5,
    parameter STRIDE = 2,
    parameter PADDING = 2,
    parameter IN_LENGTH = 180,
    parameter OUT_LENGTH = 90,
    parameter WEIGHT_FILE = "conv1_w.mem",
    parameter BIAS_FILE = "conv1_b.mem",
    parameter RELU_EN = 1
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    // Input feature BRAM read port (1-cycle registered latency)
    output logic feat_rd_en,
    output logic [$clog2(IN_CHANNELS * IN_LENGTH)-1:0] feat_rd_addr,
    input  logic signed [DATA_WIDTH-1:0] feat_rd_data,

    // Output feature BRAM write port
    output logic out_wr_en,
    output logic [$clog2(OUT_CHANNELS * OUT_LENGTH)-1:0] out_wr_addr,
    output logic signed [DATA_WIDTH-1:0] out_wr_data
);

// Counter bit widths

localparam POS_BITS = (OUT_LENGTH > 1) ? $clog2(OUT_LENGTH) : 1;
localparam OCH_BITS = (OUT_CHANNELS > 1) ? $clog2(OUT_CHANNELS) : 1;
localparam ICH_BITS = (IN_CHANNELS > 1) ? $clog2(IN_CHANNELS) : 1;
localparam TAP_BITS = (KERNEL_SIZE > 1) ? $clog2(KERNEL_SIZE) : 1;

logic [POS_BITS-1:0] pos_cnt;
logic [OCH_BITS-1:0] o_cnt;
logic [ICH_BITS-1:0] ch_cnt;
logic [TAP_BITS-1:0] tap_cnt;
logic load_bias, mac_en, mac_en_d1, write_en;   // mac_en_d1 added

// Controller

conv1d_controller #(
    .IN_CHANNELS (IN_CHANNELS),
    .OUT_CHANNELS(OUT_CHANNELS),
    .OUT_LENGTH  (OUT_LENGTH),
    .KERNEL_SIZE (KERNEL_SIZE)
) CTRL (
    .clk (clk),
    .rst (rst),
    .start(start),
    .load_bias(load_bias),
    .mac_en (mac_en),
    .mac_en_d1(mac_en_d1),     // new port
    .write_en (write_en),
    .done(done),
    .pos_cnt(pos_cnt),
    .o_cnt(o_cnt),
    .ch_cnt (ch_cnt),
    .tap_cnt(tap_cnt)
);

// Datapath

conv1d_datapath #(
    .DATA_WIDTH (DATA_WIDTH),
    .IN_CHANNELS (IN_CHANNELS),
    .OUT_CHANNELS(OUT_CHANNELS),
    .KERNEL_SIZE (KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(IN_LENGTH),
    .OUT_LENGTH (OUT_LENGTH),
    .WEIGHT_FILE (WEIGHT_FILE),
    .BIAS_FILE (BIAS_FILE),
    .RELU_EN (RELU_EN)
) DP (
    .clk(clk),
    .load_bias(load_bias),
    .mac_en(mac_en),
    .mac_en_d1(mac_en_d1),  // new port
    .write_en(write_en),
    .pos_cnt(pos_cnt),
    .o_cnt (o_cnt),
    .ch_cnt (ch_cnt),
    .tap_cnt(tap_cnt),
    .feat_rd_en (feat_rd_en),
    .feat_rd_addr(feat_rd_addr),
    .feat_rd_data(feat_rd_data),
    .out_wr_en (out_wr_en),
    .out_wr_addr (out_wr_addr),
    .out_wr_data (out_wr_data)
);

endmodule
