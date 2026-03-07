`timescale 1ns/1ps

module cnn_tb;

// -------------------------------------------------------
// Parameters
// -------------------------------------------------------

localparam DATA_WIDTH  = 16;
localparam ECG_LENGTH  = 180;
localparam KERNEL_SIZE = 5;
localparam STRIDE      = 2;
localparam PADDING     = 2;
localparam CH0         = 1;
localparam CH1         = 16;
localparam CH2         = 32;
localparam CH3         = 64;
localparam PAR_OUT     = 16;
localparam NUM_CLASSES = 2;
localparam NUM_CASES   = 50;

localparam LEN1 = ((ECG_LENGTH + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;
localparam LEN2 = ((LEN1       + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;
localparam LEN3 = ((LEN2       + 2*PADDING - KERNEL_SIZE) / STRIDE) + 1;

localparam CLK_PERIOD  = 10;

// -------------------------------------------------------
// DUT signals
// -------------------------------------------------------

logic clk, rst, start, done;
logic prediction;

// -------------------------------------------------------
// DUT
// -------------------------------------------------------

cnn_top #(
    .DATA_WIDTH(DATA_WIDTH),
    .ECG_LENGTH(ECG_LENGTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .CH0(CH0),
    .CH1(CH1),
    .CH2(CH2),
    .CH3(CH3),
    .PAR_OUT(PAR_OUT),
    .NUM_CLASSES(NUM_CLASSES)
) DUT (
    .clk(clk),
    .rst(rst),
    .start(start),
    .done(done),
    .prediction(prediction)
);

// -------------------------------------------------------
// Clock
// -------------------------------------------------------

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// -------------------------------------------------------
// Test vector storage
// all_inputs: 50 cases * 180 samples = 9000 entries
// all_expected: 50 entries (0 or 1)
// -------------------------------------------------------

logic signed [DATA_WIDTH-1:0] all_inputs   [NUM_CASES*ECG_LENGTH];
logic                         all_expected [NUM_CASES];

int pass_count, fail_count;

// -------------------------------------------------------
// Task: reload weights after reset
// Reset clears all flip flops including weight/bias mems
// so we reload after every reset
// -------------------------------------------------------

task load_weights;
    $readmemh("conv1_weight.hex", DUT.CONV1.DP.weight_mem);
    $readmemh("conv1_bias.hex",   DUT.CONV1.DP.bias_mem);
    $readmemh("conv2_weight.hex", DUT.CONV2.DP.weight_mem);
    $readmemh("conv2_bias.hex",   DUT.CONV2.DP.bias_mem);
    $readmemh("conv3_weight.hex", DUT.CONV3.DP.weight_mem);
    $readmemh("conv3_bias.hex",   DUT.CONV3.DP.bias_mem);
    $readmemh("fc_weight.hex",    DUT.FC.DP.weight_mem);
    $readmemh("fc_bias.hex",      DUT.FC.DP.bias_mem);
endtask

// -------------------------------------------------------
// Main stimulus
// -------------------------------------------------------

initial begin

    $readmemh("inputs.hex",  all_inputs);
    $readmemb("outputs.hex", all_expected);
    $display("Test vectors loaded: %0d cases x %0d samples", NUM_CASES, ECG_LENGTH);

    pass_count = 0;
    fail_count = 0;

    // Initial reset
    rst   = 1;
    start = 0;
    repeat(5) @(posedge clk);
    rst = 0;
    repeat(2) @(posedge clk);

    // Load weights once after initial reset
    load_weights();
    $display("Weights loaded.");
    $display("============================================================");

    // -------------------------------------------------------
    // Run all 50 test cases
    // -------------------------------------------------------

    for(int tc=0; tc<NUM_CASES; tc++) begin

        // Load ECG input for this test case into ecg_mem
        for(int i=0; i<ECG_LENGTH; i++)
            DUT.ecg_mem[0][i] = all_inputs[tc*ECG_LENGTH + i];

        // Assert start for one cycle
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        // Wait for inference to complete
        @(posedge done);
        @(posedge clk);

        // Compare RTL prediction vs Python expected output
        if(prediction === all_expected[tc]) begin
            $display("Test %2d: PASS | RTL=%0d  Expected=%0d  (%s)",
                     tc+1, prediction, all_expected[tc],
                     all_expected[tc] ? "Arrhythmia" : "Normal    ");
            pass_count++;
        end
        else begin
            $display("Test %2d: FAIL | RTL=%0d  Expected=%0d  (%s) <---",
                     tc+1, prediction, all_expected[tc],
                     all_expected[tc] ? "Arrhythmia" : "Normal    ");
            fail_count++;
        end

        // Reset between test cases to clear shared memories and FSM state
        // but NOT weight memories — reload after reset
        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        load_weights();

    end

    // -------------------------------------------------------
    // Final summary
    // -------------------------------------------------------

    $display("============================================================");
    $display("FINAL RESULTS");
    $display("  Total cases  : %0d", NUM_CASES);
    $display("  Passed       : %0d", pass_count);
    $display("  Failed       : %0d", fail_count);
    $display("  RTL Accuracy : %0.1f%%", (pass_count * 100.0) / NUM_CASES);
    $display("  Python Acc   : 96.0%%");
    $display("============================================================");

    if(pass_count == NUM_CASES)
        $display("ALL TESTS PASSED — RTL matches Python model exactly.");
    else
        $display("Some tests failed — check Q8.8 rescaling or GAP approximation.");

    $finish;
end

// -------------------------------------------------------
// Timeout watchdog
// Per test case estimate:
//   Conv1: 90 * 1 * (1*5)  =    450 cycles
//   Conv2: 45 * 2 * (16*5) =  7,200 cycles
//   Conv3: 23 * 4 * (32*5) = 14,720 cycles
//   GAP  : 23 cycles
//   FC   : 64 cycles
//   Total: ~25,000 cycles per case
//   50 cases + resets + overhead: ~1,500,000 cycles
// -------------------------------------------------------

initial begin
    #(CLK_PERIOD * 2_000_000);
    $display("TIMEOUT: simulation exceeded 2M cycles.");
    $finish;
end

endmodule
