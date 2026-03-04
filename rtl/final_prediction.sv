module predict_binary #(
    parameter DATA_WIDTH  = 16,
    parameter NUM_CLASSES = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    // FC layer scores
    input  logic signed [DATA_WIDTH-1:0] scores [NUM_CLASSES][1],

    // prediction output
    output logic prediction
);

always_ff @(posedge clk) begin
    if (rst) begin
        prediction <= 0;
        done       <= 0;
    end
    else begin
        done <= 0;

        if (start) begin
            // Binary comparison (Argmax for 2 classes)
            // prediction = 1 → Arrhythmia detected
            // prediction = 0 → Normal ECG
            prediction <= (scores[1][0] > scores[0][0]);

            done <= 1;
        end
    end
end

endmodule