module ecg_rom #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH  = 180,          // ECG_LENGTH
    parameter MEM_FILE  = "inputs_ecg_180.hex"
)(
    input  logic clk,

    // Read port
    input  logic rd_en,
    input  logic [$clog2(DEPTH)-1:0] rd_addr,
    output logic signed [DATA_WIDTH-1:0]  rd_data
);

(* rom_style = "block" *) logic signed [DATA_WIDTH-1:0] mem [DEPTH];

initial $readmemh(MEM_FILE, mem);

always_ff @(posedge clk) begin
    if (rd_en)
        rd_data <= mem[rd_addr];
end

endmodule
