module feature_bram #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 1440          // default CH1*LEN1 = 16*90
)(
    input logic clk,

    // Write port
    input  logic wr_en,
    input  logic [$clog2(DEPTH)-1:0] wr_addr,
    input  logic signed [DATA_WIDTH-1:0] wr_data,

    // Read port  (1-cycle registered latency)
    input  logic rd_en,
    input  logic [$clog2(DEPTH)-1:0] rd_addr,
    output logic signed [DATA_WIDTH-1:0] rd_data
);

// Memory array 
(* ram_style = "block" *) logic signed [DATA_WIDTH-1:0] mem [DEPTH];

// Synchronous write
always_ff @(posedge clk) begin
    if (wr_en)
        mem[wr_addr] <= wr_data;
end

// Synchronous registered read  
always_ff @(posedge clk) begin
    if (rd_en)
        rd_data <= mem[rd_addr];
end

endmodule
