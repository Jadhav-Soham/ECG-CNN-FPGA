module cnn_top #(
    parameter DATA_WIDTH  = 16,

    // ECG input
    parameter ECG_LENGTH  = 180,

    // Shared conv parameters
    parameter KERNEL_SIZE = 5,
    parameter STRIDE      = 2,
    parameter PADDING     = 2,

    // Channel progression
    parameter CH0         = 1,    // ECG input channels
    parameter CH1         = 16,   // Conv1 output channels
    parameter CH2         = 32,   // Conv2 output channels
    parameter CH3         = 64,   // Conv3 output channels

    // Parallelism in conv engine
    parameter PAR_OUT     = 16,

    // Classification
    parameter NUM_CLASSES = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,
    output logic [$clog2(NUM_CLASSES)-1:0] prediction
);

// Derived feature map lengths — single source of truth

localparam LEN1 = ((ECG_LENGTH + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;  // 90
localparam LEN2 = ((LEN1       + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;  // 45
localparam LEN3 = ((LEN2       + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;  // 23


// Shared memories

logic signed [DATA_WIDTH-1:0] ecg_mem [CH0][ECG_LENGTH];  // loaded externally before start
logic signed [DATA_WIDTH-1:0] mem_1_2 [CH1][LEN1];        // Conv1 out = Conv2 in
logic signed [DATA_WIDTH-1:0] mem_2_3 [CH2][LEN2];        // Conv2 out = Conv3 in
logic signed [DATA_WIDTH-1:0] mem_3   [CH3][LEN3];        // Conv3 out = GAP in
logic signed [DATA_WIDTH-1:0] gap_out [CH3][1];
logic signed [DATA_WIDTH-1:0] fc_out  [NUM_CLASSES][1];

// Inter-module signals

logic conv1_start, conv1_done;
logic conv2_start, conv2_done;
logic conv3_start, conv3_done;
logic gap_start,   gap_done;
logic fc_start,    fc_done;
logic pred_start,  pred_done;


// Conv1: CH0 → CH1, ECG_LENGTH → LEN1

conv1d_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(CH0),
    .OUT_CHANNELS(CH1),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(ECG_LENGTH),
    .OUT_LENGTH(LEN1),
    .PAR_OUT(PAR_OUT)
) CONV1 (
    .clk(clk),
    .rst(rst),
    .start(conv1_start),
    .done(conv1_done),
    .feature_mem(ecg_mem),
    .output_mem(mem_1_2)
);


// Conv2: CH1 → CH2, LEN1 → LEN2

conv1d_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(CH1),
    .OUT_CHANNELS(CH2),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(LEN1),
    .OUT_LENGTH(LEN2),
    .PAR_OUT(PAR_OUT)
) CONV2 (
    .clk(clk),
    .rst(rst),
    .start(conv2_start),
    .done(conv2_done),
    .feature_mem(mem_1_2),
    .output_mem(mem_2_3)
);


// Conv3: CH2 → CH3, LEN2 → LEN3

conv1d_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(CH2),
    .OUT_CHANNELS(CH3),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IN_LENGTH(LEN2),
    .OUT_LENGTH(LEN3),
    .PAR_OUT(PAR_OUT)
) CONV3 (
    .clk(clk),
    .rst(rst),
    .start(conv3_start),
    .done(conv3_done),
    .feature_mem(mem_2_3),
    .output_mem(mem_3)
);


// GAP: CH3 channels, LEN3 positions → CH3 values

gap #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(CH3),
    .IN_LENGTH(LEN3)
) GAP (
    .clk(clk),
    .rst(rst),
    .start(gap_start),
    .done(gap_done),
    .gap_in(mem_3),
    .gap_out(gap_out)
);


// FC: CH3 inputs → NUM_CLASSES outputs

conv1d_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(CH3),
    .OUT_CHANNELS(NUM_CLASSES),
    .KERNEL_SIZE(1),
    .STRIDE(1),
    .PADDING(0),
    .IN_LENGTH(1),
    .OUT_LENGTH(1),
    .PAR_OUT(NUM_CLASSES)
) FC (
    .clk(clk),
    .rst(rst),
    .start(fc_start),
    .done(fc_done),
    .feature_mem(gap_out),
    .output_mem(fc_out)
);


// Predict

predict_binary #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_CLASSES(NUM_CLASSES)
) PREDICT (
    .clk(clk),
    .rst(rst),
    .start(pred_start),
    .done(pred_done),
    .scores(fc_out),
    .prediction(prediction)
);


// Top-level FSM

localparam S_IDLE   = 0,
           S_CONV1  = 1,
           S_CONV2  = 2,
           S_CONV3  = 3,
           S_GAP    = 4,
           S_FC     = 5,
           S_PRED   = 6,
           S_DONE   = 7;

logic [2:0] state;

always_ff @(posedge clk) begin
    if(rst) begin
        state      <= S_IDLE;
        conv1_start <= 0;
        conv2_start <= 0;
        conv3_start <= 0;
        gap_start   <= 0;
        fc_start    <= 0;
        pred_start  <= 0;
        done        <= 0;
    end
    else begin
        // Default: deassert all start pulses
        conv1_start <= 0;
        conv2_start <= 0;
        conv3_start <= 0;
        gap_start   <= 0;
        fc_start    <= 0;
        pred_start  <= 0;
        done        <= 0;

        case(state)

        S_IDLE: begin
            if(start) begin
                conv1_start <= 1;
                state       <= S_CONV1;
            end
        end

        S_CONV1: begin
            if(conv1_done) begin
                conv2_start <= 1;
                state       <= S_CONV2;
            end
        end

        S_CONV2: begin
            if(conv2_done) begin
                conv3_start <= 1;
                state       <= S_CONV3;
            end
        end

        S_CONV3: begin
            if(conv3_done) begin
                gap_start <= 1;
                state     <= S_GAP;
            end
        end

        S_GAP: begin
            if(gap_done) begin
                fc_start <= 1;
                state    <= S_FC;
            end
        end

        S_FC: begin
            if(fc_done) begin
                pred_start <= 1;
                state      <= S_PRED;
            end
        end

        S_PRED: begin
            if(pred_done) begin
                done  <= 1;
                state <= S_DONE;
            end
        end

        S_DONE:
            state <= S_IDLE;

        endcase
    end
end

endmodule
