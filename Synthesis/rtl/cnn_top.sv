module cnn_top #(
    parameter DATA_WIDTH  = 16,
    parameter ECG_LENGTH  = 180,

    parameter KERNEL_SIZE = 5,
    parameter STRIDE = 2,
    parameter PADDING = 2,

    parameter CH0 = 1,
    parameter CH1 = 16,
    parameter CH2 = 32,
    parameter CH3 = 64,
    parameter NUM_CLASSES = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,
    output logic [$clog2(NUM_CLASSES)-1:0] prediction
);

//feature-map lengths

localparam LEN1 = ((ECG_LENGTH + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;    // 90
localparam LEN2 = ((LEN1 + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;          // 45
localparam LEN3 = ((LEN2 + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;          // 23

// BRAM depths

localparam D_ECG = CH0 * ECG_LENGTH;  //   180
localparam D_12 = CH1 * LEN1;         //  1440
localparam D_23 = CH2 * LEN2;         //  1440
localparam D_3  = CH3 * LEN3;         //  1472


//Indicators

logic conv1_start, conv1_done;
logic conv2_start, conv2_done;
logic conv3_start, conv3_done;
logic gap_start, gap_done;
logic fc_start, fc_done;
logic pred_start, pred_done;


// Small register arrays (not BRAMs)

logic signed [DATA_WIDTH-1:0] gap_out [CH3];
logic signed [DATA_WIDTH-1:0] fc_out  [NUM_CLASSES];


// BRAM INSTANCES

//ECG input ROM
logic ecg_rd_en;
logic [$clog2(D_ECG)-1:0] ecg_rd_addr;
logic signed [DATA_WIDTH-1:0] ecg_rd_data;

ecg_rom #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH     (D_ECG),
    .MEM_FILE  ("E:/ECG_FPGA/weights/test_vectors/inputs_ecg_180.hex")
) ECG_ROM (
    .clk    (clk),
    .rd_en  (ecg_rd_en),
    .rd_addr(ecg_rd_addr),
    .rd_data(ecg_rd_data)
);

//Conv1 → Conv2 buffer
logic b12_wr_en,  b12_rd_en;
logic [$clog2(D_12)-1:0] b12_wr_addr, b12_rd_addr;
logic signed [DATA_WIDTH-1:0] b12_wr_data, b12_rd_data;

feature_bram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(D_12)) BRAM_12 (
    .clk    (clk),
    .wr_en  (b12_wr_en),  .wr_addr(b12_wr_addr), .wr_data(b12_wr_data),
    .rd_en  (b12_rd_en),  .rd_addr(b12_rd_addr), .rd_data(b12_rd_data)
);

// Conv2 → Conv3 buffer
logic                         b23_wr_en,  b23_rd_en;
logic [$clog2(D_23)-1:0]      b23_wr_addr, b23_rd_addr;
logic signed [DATA_WIDTH-1:0] b23_wr_data, b23_rd_data;

feature_bram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(D_23)) BRAM_23 (
    .clk    (clk),
    .wr_en  (b23_wr_en),  .wr_addr(b23_wr_addr), .wr_data(b23_wr_data),
    .rd_en  (b23_rd_en),  .rd_addr(b23_rd_addr), .rd_data(b23_rd_data)
);

// Conv3 → GAP buffer
logic                         b3_wr_en,   b3_rd_en;
logic [$clog2(D_3)-1:0]       b3_wr_addr, b3_rd_addr;
logic signed [DATA_WIDTH-1:0] b3_wr_data, b3_rd_data;

feature_bram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(D_3)) BRAM_3 (
    .clk    (clk),
    .wr_en  (b3_wr_en),   .wr_addr(b3_wr_addr),  .wr_data(b3_wr_data),
    .rd_en  (b3_rd_en),   .rd_addr(b3_rd_addr),  .rd_data(b3_rd_data)
);

// CONV1  —  reads ECG ROM, writes BRAM_12

logic c1_feat_rd_en;
logic [$clog2(D_ECG)-1:0] c1_feat_rd_addr;
logic c1_out_wr_en;
logic [$clog2(D_12)-1:0] c1_out_wr_addr;
logic signed [DATA_WIDTH-1:0] c1_out_wr_data;

assign ecg_rd_en    = c1_feat_rd_en;
assign ecg_rd_addr  = c1_feat_rd_addr;
assign b12_wr_en    = c1_out_wr_en;
assign b12_wr_addr  = c1_out_wr_addr;
assign b12_wr_data  = c1_out_wr_data;

conv1d_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .IN_CHANNELS (CH0),
    .OUT_CHANNELS(CH1),
    .KERNEL_SIZE (KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(ECG_LENGTH),
    .OUT_LENGTH(LEN1),
    .WEIGHT_FILE ("E:/ECG_FPGA/weights/hex/hex/conv1_weight.hex"),
    .BIAS_FILE("E:/ECG_FPGA/weights/hex/hex/conv1_bias.hex"),
    .RELU_EN(1)
) CONV1 (
    .clk(clk), .rst(rst),
    .start(conv1_start), .done(conv1_done),
    .feat_rd_en  (c1_feat_rd_en),
    .feat_rd_addr(c1_feat_rd_addr),
    .feat_rd_data(ecg_rd_data),
    .out_wr_en   (c1_out_wr_en),
    .out_wr_addr (c1_out_wr_addr),
    .out_wr_data (c1_out_wr_data)
);

// CONV2  —  reads BRAM_12, writes BRAM_23

logic c2_feat_rd_en;
logic [$clog2(D_12)-1:0] c2_feat_rd_addr;
logic c2_out_wr_en;
logic [$clog2(D_23)-1:0] c2_out_wr_addr;
logic signed [DATA_WIDTH-1:0] c2_out_wr_data;

assign b12_rd_en    = c2_feat_rd_en;
assign b12_rd_addr  = c2_feat_rd_addr;
assign b23_wr_en    = c2_out_wr_en;
assign b23_wr_addr  = c2_out_wr_addr;
assign b23_wr_data  = c2_out_wr_data;

conv1d_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .IN_CHANNELS (CH1),
    .OUT_CHANNELS(CH2),
    .KERNEL_SIZE (KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(LEN1),
    .OUT_LENGTH(LEN2),
    .WEIGHT_FILE ("E:/ECG_FPGA/weights/hex/hex/conv2_weight.hex"),
    .BIAS_FILE ("E:/ECG_FPGA/weights/hex/hex/conv2_bias.hex"),
    .RELU_EN(1)
) CONV2 (
    .clk (clk), .rst(rst),
    .start(conv2_start), .done(conv2_done),
    .feat_rd_en(c2_feat_rd_en),
    .feat_rd_addr(c2_feat_rd_addr),
    .feat_rd_data(b12_rd_data),
    .out_wr_en (c2_out_wr_en),
    .out_wr_addr(c2_out_wr_addr),
    .out_wr_data(c2_out_wr_data)
);

// CONV3  —  reads BRAM_23, writes BRAM_3

logic c3_feat_rd_en;
logic [$clog2(D_23)-1:0] c3_feat_rd_addr;
logic c3_out_wr_en;
logic [$clog2(D_3)-1:0]  c3_out_wr_addr;
logic signed [DATA_WIDTH-1:0] c3_out_wr_data;

assign b23_rd_en    = c3_feat_rd_en;
assign b23_rd_addr  = c3_feat_rd_addr;
assign b3_wr_en     = c3_out_wr_en;
assign b3_wr_addr   = c3_out_wr_addr;
assign b3_wr_data   = c3_out_wr_data;

conv1d_top #(
    .DATA_WIDTH  (DATA_WIDTH),
    .IN_CHANNELS (CH2),
    .OUT_CHANNELS(CH3),
    .KERNEL_SIZE (KERNEL_SIZE),
    .STRIDE (STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(LEN2),
    .OUT_LENGTH(LEN3),
    .WEIGHT_FILE ("E:/ECG_FPGA/weights/hex/hex/conv3_weight.hex"),
    .BIAS_FILE ("E:/ECG_FPGA/weights/hex/hex/conv3_bias.hex"),
    .RELU_EN(1)
) CONV3 (
    .clk(clk), .rst(rst),
    .start (conv3_start), .done(conv3_done),
    .feat_rd_en  (c3_feat_rd_en),
    .feat_rd_addr(c3_feat_rd_addr),
    .feat_rd_data(b23_rd_data),
    .out_wr_en   (c3_out_wr_en),
    .out_wr_addr (c3_out_wr_addr),
    .out_wr_data (c3_out_wr_data)
);


// GAP  —  reads BRAM_3, outputs to gap_out register array

gap #(
    .DATA_WIDTH (DATA_WIDTH),
    .IN_CHANNELS(CH3),
    .IN_LENGTH  (LEN3)
) GAP (
    .clk (clk), .rst(rst),
    .start(gap_start), .done(gap_done),
    .feat_rd_en (b3_rd_en),
    .feat_rd_addr(b3_rd_addr),
    .feat_rd_data(b3_rd_data),
    .gap_out(gap_out)
);

// FC  

logic fc_feat_rd_en;
logic [$clog2(CH3)-1:0] fc_feat_rd_addr;
logic signed [DATA_WIDTH-1:0]fc_feat_rd_data;
logic fc_out_wr_en;
logic [$clog2(NUM_CLASSES)-1:0] fc_out_wr_addr;
logic signed [DATA_WIDTH-1:0] fc_out_wr_data;

// Synchronous read mux 
always_ff @(posedge clk)
    fc_feat_rd_data <= gap_out[fc_feat_rd_addr];

// FC output written directly into fc_out registers
always_ff @(posedge clk)
    if (fc_out_wr_en)
        fc_out[fc_out_wr_addr] <= fc_out_wr_data;

conv1d_top #(
    .DATA_WIDTH  (DATA_WIDTH),
    .IN_CHANNELS (CH3),
    .OUT_CHANNELS(NUM_CLASSES),
    .KERNEL_SIZE (1),
    .STRIDE (1),
    .PADDING  (0),
    .IN_LENGTH(1),
    .OUT_LENGTH(1),
    .WEIGHT_FILE ("E:/ECG_FPGA/weights/hex/hex/fc_weight.hex"),
    .BIAS_FILE ("E:/ECG_FPGA/weights/hex/hex/fc_bias.hex"),
    .RELU_EN(0)
) FC (
    .clk (clk), .rst(rst),
    .start(fc_start), .done(fc_done),
    .feat_rd_en (fc_feat_rd_en),
    .feat_rd_addr(fc_feat_rd_addr),
    .feat_rd_data(fc_feat_rd_data),
    .out_wr_en (fc_out_wr_en),
    .out_wr_addr (fc_out_wr_addr),
    .out_wr_data (fc_out_wr_data)
);

// Predict

predict_binary #(
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_CLASSES(NUM_CLASSES)
) PREDICT (
    .clk (clk), .rst(rst),
    .start (pred_start), .done(pred_done),
    .scores(fc_out),
    .prediction(prediction)
);

// Top-level FSM 

localparam [2:0] S_IDLE  = 3'b000,
                 S_CONV1 = 3'b001,
                 S_CONV2 = 3'b010,
                 S_CONV3 = 3'b011,
                 S_GAP   = 3'b100,
                 S_FC    = 3'b101,
                 S_PRED  = 3'b110,
                 S_DONE  = 3'b111;

logic [2:0] state;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= S_IDLE;
        conv1_start <= 1'b0; conv2_start <= 1'b0;
        conv3_start <= 1'b0; gap_start   <= 1'b0;
        fc_start <= 1'b0; pred_start  <= 1'b0;
        done <= 1'b0;
    end
    else begin
        conv1_start <= 1'b0; conv2_start <= 1'b0;
        conv3_start <= 1'b0; gap_start   <= 1'b0;
        fc_start <= 1'b0; pred_start  <= 1'b0;
        done<= 1'b0;

        case (state)
        S_IDLE:  if (start) begin conv1_start <= 1'b1; state <= S_CONV1; end
        S_CONV1: if (conv1_done) begin conv2_start <= 1'b1; state <= S_CONV2; end
        S_CONV2: if (conv2_done) begin conv3_start <= 1'b1; state <= S_CONV3; end
        S_CONV3: if (conv3_done) begin gap_start <= 1'b1; state <= S_GAP;   end
        S_GAP:   if (gap_done) begin fc_start <= 1'b1; state <= S_FC;    end
        S_FC:    if (fc_done) begin pred_start <= 1'b1; state <= S_PRED;  end
        S_PRED:  if (pred_done) begin done <= 1'b1; state <= S_DONE;  end
        S_DONE:  state <= S_IDLE;
        default: state <= S_IDLE;
        endcase
    end
end

endmodule
