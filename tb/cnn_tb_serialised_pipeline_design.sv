// ============================================================================
// cnn_top_tb.sv
//
// Testbench for cnn_top — PAR_OUT=1 fully-serial pipelined design.
//
// Test flow per sample
// ─────────────────────
//  1. Write 180 ECG words into ECG_BRAM via ecg_wr_en/addr/data port
//     (one word per clock cycle — 180 cycles total)
//  2. Assert start for 1 cycle
//  3. Wait for done
//  4. Capture prediction, debug_fc_out[0/1], debug_gap_out[0..3]
//  5. Compare against expected, log result
//  6. Reset DUT before next sample
//
// Intermediate values logged
// ───────────────────────────
//  debug_fc_out[0/1]     : raw class scores — tells us if the bug is in
//                          the conv/gap pipeline or just the final argmax
//  debug_gap_out[0..3]   : first 4 GAP outputs — sanity check on Conv3
//
// Files
// ──────
//  inputs.hex   : 9000 lines, one 4-digit hex word per line (50 × 180)
//  outputs.hex  : 50 lines, one binary digit per line (0 or 1)
//  results.log  : written by this testbench
// ============================================================================

`timescale 1ns/1ps

module cnn_top_tb;

// -------------------------------------------------------------------------
// Parameters
// -------------------------------------------------------------------------
localparam DATA_WIDTH  = 16;
localparam ECG_LENGTH  = 180;
localparam KERNEL_SIZE = 5;
localparam STRIDE      = 2;
localparam PADDING     = 2;
localparam CH0         = 1;
localparam CH1         = 16;
localparam CH2         = 32;
localparam CH3         = 64;
localparam NUM_CLASSES = 2;
localparam N_SAMPLES   = 50;
localparam CLK_PERIOD  = 10; // 100 MHz → 10 ns

// -------------------------------------------------------------------------
// DUT ports
// -------------------------------------------------------------------------
logic clk, rst, start, done;
logic [$clog2(NUM_CLASSES)-1:0] prediction;

// Debug observation ports
logic signed [DATA_WIDTH-1:0] debug_fc_out  [NUM_CLASSES];
logic signed [DATA_WIDTH-1:0] debug_gap_out [CH3];

// ECG BRAM write port (testbench drives these to load each sample)
logic                         ecg_wr_en;
logic [$clog2(CH0*ECG_LENGTH)-1:0] ecg_wr_addr;
logic signed [DATA_WIDTH-1:0] ecg_wr_data;

// -------------------------------------------------------------------------
// DUT instantiation
// -------------------------------------------------------------------------
cnn_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .ECG_LENGTH (ECG_LENGTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE     (STRIDE),
    .PADDING    (PADDING),
    .CH0        (CH0),
    .CH1        (CH1),
    .CH2        (CH2),
    .CH3        (CH3),
    .NUM_CLASSES(NUM_CLASSES)
) DUT (
    .clk          (clk),
    .rst          (rst),
    .start        (start),
    .done         (done),
    .prediction   (prediction),
    .debug_fc_out (debug_fc_out),
    .debug_gap_out(debug_gap_out),
    .ecg_wr_en    (ecg_wr_en),
    .ecg_wr_addr  (ecg_wr_addr),
    .ecg_wr_data  (ecg_wr_data)
);

// -------------------------------------------------------------------------
// Clock generation
// -------------------------------------------------------------------------
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// -------------------------------------------------------------------------
// Test vector storage
// -------------------------------------------------------------------------
// inputs.hex  : 9000 lines, one 16-bit hex word per line
// outputs.hex : 50 lines, one binary digit per line
logic [DATA_WIDTH-1:0] all_inputs [N_SAMPLES * ECG_LENGTH];
logic [0:0]            expected   [N_SAMPLES];

// -------------------------------------------------------------------------
// Result tracking
// -------------------------------------------------------------------------
integer correct;
integer log_fd;
integer s, i;

// Captured intermediate values
logic signed [DATA_WIDTH-1:0] cap_fc0, cap_fc1;
logic signed [DATA_WIDTH-1:0] cap_gap [4];
logic                         pred_result;

// -------------------------------------------------------------------------
// Task: hard reset — 5 cycles of rst=1 then release
// -------------------------------------------------------------------------
task automatic do_reset();
    @(negedge clk);
    rst        = 1;
    start      = 0;
    ecg_wr_en  = 0;
    ecg_wr_addr = 0;
    ecg_wr_data = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    rst = 0;
    repeat(2) @(posedge clk);
endtask

// -------------------------------------------------------------------------
// Task: write one ECG sample (180 words) into ECG_BRAM
// Uses the ecg_wr_en/addr/data port on cnn_top.
// One word per clock cycle, starting at address 0.
// -------------------------------------------------------------------------
task automatic load_sample(input integer sample_idx);
    integer base_idx;
    integer w;
    base_idx = sample_idx * ECG_LENGTH;

    @(negedge clk);
    for (w = 0; w < ECG_LENGTH; w++) begin
        ecg_wr_en   = 1;
        ecg_wr_addr = w[$clog2(CH0*ECG_LENGTH)-1:0];
        ecg_wr_data = all_inputs[base_idx + w];
        @(negedge clk);
    end
    ecg_wr_en  = 0;
    ecg_wr_addr = 0;
    ecg_wr_data = 0;
    // Extra cycle to let last write settle in BRAM
    @(posedge clk);
endtask

// -------------------------------------------------------------------------
// Task: run one inference — assert start, wait for done with timeout
// -------------------------------------------------------------------------
task automatic run_inference();
    // Pulse start for 1 cycle
    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;

    // Wait for done with a timeout
    // Max cycles upper bound (conservative):
    //   Conv1: 90 pos × 16 ch × (1 + 5 + 1 + 1) = ~11520
    //   Conv2: 45 pos × 32 ch × (1 + 80 + 1 + 1) = ~120960
    //   Conv3: 23 pos × 64 ch × (1 + 160 + 1 + 1) = ~241216
    //   GAP  : 64 ch × 23 pos × 2 = ~2944
    //   FC   : 1 pos × 2 ch × (1 + 64 + 1 + 1) = ~134
    //   Total ≈ 380000 cycles — use 1M as safe timeout
    fork
        begin : wait_done_blk
            @(posedge done);
            disable timeout_blk;
        end
        begin : timeout_blk
            repeat(2_000_000) @(posedge clk);
            $display("  [TIMEOUT] Sample %0d exceeded 2M cycles", s);
            disable wait_done_blk;
        end
    join

    // Let outputs settle for 2 cycles after done
    repeat(2) @(posedge clk);
endtask

// -------------------------------------------------------------------------
// Main test sequence
// -------------------------------------------------------------------------
initial begin : main_test

    // Load all test vectors at elaboration time
    $readmemh("inputs.hex",  all_inputs);
    $readmemb("outputs.hex", expected);

    // Open results log
    log_fd = $fopen("results.log", "w");

    // Log header
    $fdisplay(log_fd, "CNN Top — Accuracy Test Results");
    $fdisplay(log_fd, "================================");
    $fdisplay(log_fd, "%-6s | %-4s | %-4s | %-12s | %-12s | %-8s | %-8s | %-8s | %-8s | %s",
              "Sample", "Exp", "Got",
              "fc_out[0]", "fc_out[1]",
              "gap[0]", "gap[1]", "gap[2]", "gap[3]",
              "Result");
    $fdisplay(log_fd, "%s", {"-------+------+------+--------------+--------------+----------+----------+----------+----------+--------"});

    correct = 0;

    // Initial reset
    do_reset();

    // -----------------------------------------------------------------------
    // Main loop — one inference per sample
    // -----------------------------------------------------------------------
    for (s = 0; s < N_SAMPLES; s++) begin

        // Step 1: load sample into ECG BRAM
        load_sample(s);

        // Step 2: run inference
        run_inference();

        // Step 3: capture outputs
        pred_result = prediction;
        cap_fc0     = debug_fc_out[0];
        cap_fc1     = debug_fc_out[1];
        cap_gap[0]  = debug_gap_out[0];
        cap_gap[1]  = debug_gap_out[1];
        cap_gap[2]  = debug_gap_out[2];
        cap_gap[3]  = debug_gap_out[3];

        // Step 4: compare and log
        if (pred_result == expected[s][0]) begin
            correct++;
            $fdisplay(log_fd, "%-6d | %-4b | %-4b | %-12d | %-12d | %-8d | %-8d | %-8d | %-8d | PASS",
                      s, expected[s][0], pred_result,
                      cap_fc0, cap_fc1,
                      cap_gap[0], cap_gap[1], cap_gap[2], cap_gap[3]);
            $display("  Sample %3d: PASS  exp=%0b got=%0b  fc=[%0d, %0d]",
                     s, expected[s][0], pred_result, cap_fc0, cap_fc1);
        end
        else begin
            $fdisplay(log_fd, "%-6d | %-4b | %-4b | %-12d | %-12d | %-8d | %-8d | %-8d | %-8d | FAIL ***",
                      s, expected[s][0], pred_result,
                      cap_fc0, cap_fc1,
                      cap_gap[0], cap_gap[1], cap_gap[2], cap_gap[3]);
            $display("  Sample %3d: FAIL  exp=%0b got=%0b  fc=[%0d, %0d]  gap=[%0d,%0d,%0d,%0d]",
                     s, expected[s][0], pred_result,
                     cap_fc0, cap_fc1,
                     cap_gap[0], cap_gap[1], cap_gap[2], cap_gap[3]);
        end

        // Step 5: reset between samples to clear all pipeline state
        do_reset();

    end

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $fdisplay(log_fd, "");
    $fdisplay(log_fd, "========================================");
    $fdisplay(log_fd, "TOTAL   : %0d / %0d samples", correct, N_SAMPLES);
    $fdisplay(log_fd, "ACCURACY: %0.2f%%", (100.0 * correct) / N_SAMPLES);
    $fdisplay(log_fd, "========================================");
    $fdisplay(log_fd, "");
    $fdisplay(log_fd, "Diagnosis guide:");
    $fdisplay(log_fd, "  If fc_out scores are near zero for all samples     → pipeline latency bug");
    $fdisplay(log_fd, "  If fc_out scores are large but wrong sign          → weight index mapping bug");
    $fdisplay(log_fd, "  If gap_out values are zero or garbage              → conv3/BRAM read bug");
    $fdisplay(log_fd, "  If scores look reasonable but prediction wrong     → Q8.8 shift-by-1 bug");

    $display("");
    $display("============================================");
    $display("ACCURACY: %0d / %0d = %0.2f%%",
             correct, N_SAMPLES, (100.0 * correct) / N_SAMPLES);
    $display("============================================");
    $display("Full details written to results.log");

    $fclose(log_fd);
    $finish;

end

// -------------------------------------------------------------------------
// Absolute simulation watchdog
// -------------------------------------------------------------------------
initial begin : watchdog
    // 50 samples × 2M cycles × 10 ns = 1 second sim time limit
    #(50 * 2_000_000 * CLK_PERIOD * 1ns);
    $display("WATCHDOG TRIGGERED: simulation took too long");
    $fclose(log_fd);
    $finish;
end

endmodule
