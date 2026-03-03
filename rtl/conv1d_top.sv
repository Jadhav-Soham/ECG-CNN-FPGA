module conv1d_top #(
parameter DATA_WIDTH   = 16,
parameter IN_CHANNELS  = 32,
parameter OUT_CHANNELS = 64,
parameter KERNEL_SIZE  = 5,
parameter STRIDE       = 2,
parameter PADDING      = 2,
parameter IN_LENGTH    = 90,
parameter OUT_LENGTH   = 45,
parameter PAR_OUT      = 16
)(
input logic clk,
input logic rst,
input logic start,
output logic done,

//Shared memories
input logic signed [DATA_WIDTH-1:0]
feature_mem [IN_CHANNELS][IN_LENGTH],

output logic signed [DATA_WIDTH-1:0]
output_mem [OUT_CHANNELS][OUT_LENGTH]
);

logic load_bias,mac_en,write_en;

logic [$clog2(OUT_LENGTH)-1:0] pos_cnt;
logic [$clog2(IN_CHANNELS)-1:0]  ch_cnt;
logic [$clog2(KERNEL_SIZE)-1:0] tap_cnt;
logic [$clog2(OUT_CHANNELS/PAR_OUT)-1:0] grp_cnt;

conv1d_controller #(
.IN_CHANNELS(IN_CHANNELS),
.OUT_CHANNELS(OUT_CHANNELS),
.OUT_LENGTH(OUT_LENGTH),
.KERNEL_SIZE(KERNEL_SIZE),
.PAR_OUT(PAR_OUT)
) CTRL (
.clk(clk),
.rst(rst),
.start(start),

.load_bias(load_bias),
.mac_en(mac_en),
.write_en(write_en),
.done(done),

.pos_cnt(pos_cnt),
.ch_cnt(ch_cnt),
.tap_cnt(tap_cnt),
.grp_cnt(grp_cnt)
);

conv1d_datapath #(
.DATA_WIDTH(DATA_WIDTH),
.IN_CHANNELS(IN_CHANNELS),
.OUT_CHANNELS(OUT_CHANNELS),
.KERNEL_SIZE(KERNEL_SIZE),
.STRIDE(STRIDE),
.PADDING(PADDING),
.IN_LENGTH(IN_LENGTH),
.OUT_LENGTH(OUT_LENGTH),
.PAR_OUT(PAR_OUT)

) DP (
.clk(clk),

.load_bias(load_bias),
.mac_en(mac_en),
.write_en(write_en),

.pos_cnt(pos_cnt),
.ch_cnt(ch_cnt),
.tap_cnt(tap_cnt),
.grp_cnt(grp_cnt),

.feature_mem(feature_mem),
.output_mem(output_mem)
);

endmodule