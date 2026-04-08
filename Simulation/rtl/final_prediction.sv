module predict_binary #(
    parameter DATA_WIDTH  = 16,
    parameter NUM_CLASSES = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    // FC layer scores — 1-D register array [NUM_CLASSES]
    input  logic signed [DATA_WIDTH-1:0] scores [NUM_CLASSES],

    output logic prediction
);

always_ff @(posedge clk) begin
    if (rst) begin
        prediction <= 1'b0;
        done       <= 1'b0;
    end
    else begin
        done <= 1'b0;
        if (start) begin
            prediction <= (scores[1] > scores[0]);
            done <= 1'b1;
        end
    end
end

endmodule
