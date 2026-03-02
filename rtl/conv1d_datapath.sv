module conv1d_datapath #(
parameter DATA_WIDTH   = 16,
parameter IN_CHANNELS  = 32,
parameter OUT_CHANNELS = 64,
parameter KERNEL_SIZE  = 5,
parameter STRIDE       = 2,
parameter PADDING      = 2,
parameter IN_LENGTH    = 64,
parameter OUT_LENGTH   = 32,
parameter PAR_OUT      = 16
)(
input  logic clk,

// control inputs
input logic load_bias,
input logic mac_en,
input logic write_en,

input logic [$clog2(OUT_LENGTH)-1:0] pos_cnt,
input logic [$clog2(IN_CHANNELS)-1:0] ch_cnt,
input logic [$clog2(KERNEL_SIZE)-1:0] tap_cnt,
input logic [$clog2(OUT_CHANNELS/PAR_OUT)-1:0] grp_cnt,

//Shared memories
input logic signed [DATA_WIDTH-1:0]
feature_mem [IN_CHANNELS][IN_LENGTH],

output logic signed [DATA_WIDTH-1:0]
output_mem [OUT_CHANNELS][OUT_LENGTH]
);

// Memories

(* ram_style = "block" *) logic signed [DATA_WIDTH-1:0]
weight_mem [OUT_CHANNELS][IN_CHANNELS][KERNEL_SIZE];

(* ram_style = "block" *) logic signed [DATA_WIDTH-1:0]
bias_mem [OUT_CHANNELS];


// Address generator

localparam ADDR_WIDTH = $clog2(IN_LENGTH + PADDING + KERNEL_SIZE);
logic signed [ADDR_WIDTH:0] addr;
logic signed [DATA_WIDTH-1:0] sample;

always_comb begin           //changed to combinational, so that it updates immediately. Else it was lagging by a cycle 
    addr = pos_cnt*STRIDE + tap_cnt - PADDING;

    if(addr < 0 || addr >= IN_LENGTH)
        sample = 0;
    else
        sample = feature_mem[ch_cnt][addr];
end


// Accumulators

localparam ACC_WIDTH = 2*DATA_WIDTH + $clog2(IN_CHANNELS*KERNEL_SIZE);
logic signed [ACC_WIDTH-1:0] acc [PAR_OUT];

integer o;

// Datapath operations

always_ff @(posedge clk) begin

    // LOAD BIAS
    if(load_bias) begin
        for(o=0;o<PAR_OUT;o++)
            acc[o] <= bias_mem[grp_cnt*PAR_OUT+o];
    end

    // MAC
    else if(mac_en) begin
        for(o=0;o<PAR_OUT;o++)
            acc[o] <= acc[o] + (sample * weight_mem[grp_cnt*PAR_OUT+o][ch_cnt][tap_cnt]);
    end

    // WRITE OUTPUT
    else if(write_en) begin
        for(o=0;o<PAR_OUT;o++)
            output_mem[grp_cnt*PAR_OUT+o][pos_cnt] <= (acc[o][ACC_WIDTH-1]) ? '0 : acc[o][DATA_WIDTH-1:0];          //ReLU taken care of 
    end
end

endmodule