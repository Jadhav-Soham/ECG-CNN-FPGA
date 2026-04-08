module conv1d_controller #(
    parameter IN_CHANNELS  = 1,
    parameter OUT_CHANNELS = 16,
    parameter OUT_LENGTH   = 90,
    parameter KERNEL_SIZE  = 5
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic load_bias,
    output logic mac_en,
    output logic mac_en_d1,
    output logic write_en,
    output logic done,

    // counters 
    output logic [((OUT_LENGTH > 1) ? $clog2(OUT_LENGTH): 1)-1:0] pos_cnt,
    output logic [((OUT_CHANNELS > 1) ? $clog2(OUT_CHANNELS): 1)-1:0] o_cnt,
    output logic [((IN_CHANNELS > 1) ? $clog2(IN_CHANNELS): 1)-1:0] ch_cnt,
    output logic [((KERNEL_SIZE > 1) ? $clog2(KERNEL_SIZE): 1)-1:0] tap_cnt
);

// FSM states

localparam IDLE   = 3'd0,
           LOAD   = 3'd1,   
           MAC    = 3'd2,   
           DRAIN1 = 3'd3,  
           DRAIN2 = 3'd4,  
           WRITE  = 3'd5,   
           NEXT   = 3'd6,   
           DONE   = 3'd7;

logic [2:0] state;

// Un-delayed 
logic load_bias_raw, mac_en_raw, write_en_raw;

// FSM
always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        pos_cnt <= '0;
        o_cnt <= '0;
        ch_cnt <= '0;
        tap_cnt <= '0;
    end
    else begin
        case (state)

        IDLE:
            if (start) begin
                pos_cnt <= '0;
                o_cnt <= '0;
                state <= LOAD;
            end

        LOAD: begin
            ch_cnt <= '0;
            tap_cnt<= '0;
            state <= MAC;
        end

        MAC: begin
            if (tap_cnt < KERNEL_SIZE - 1) begin
                tap_cnt <= tap_cnt + 1'b1;
                state <= MAC;
            end
            else begin
                tap_cnt <= '0;
                if (ch_cnt < IN_CHANNELS - 1) begin
                    ch_cnt <= ch_cnt + 1'b1;
                    state <= MAC;
                end
                else
                    state <= DRAIN1;  // start flushing pipeline
            end
        end

        // DRAIN1: last w_rd_addr_comb → w_rd_addr_reg FF
        // counters frozen — no new addresses presented
        DRAIN1:
            state <= DRAIN2;

        // DRAIN2: last w_rd_addr_reg → weight BRAM → w_rd_data
        // mac_en_raw fires here so mac_en fires next cycle (2-cycle delay from MAC)
        
        DRAIN2:
            state <= WRITE;

        WRITE:
            state <= NEXT;

        NEXT: begin
            if (o_cnt < OUT_CHANNELS - 1) begin
                o_cnt <= o_cnt + 1'b1;
                state <= LOAD;
            end
            else begin
                o_cnt <= '0;
                if (pos_cnt < OUT_LENGTH - 1) begin
                    pos_cnt <= pos_cnt + 1'b1;
                    state <= LOAD;
                end
                else
                    state <= DONE;
            end
        end

        DONE:
            state <= IDLE;

        default: state <= IDLE;

        endcase
    end
end

// Raw control decode
// mac_en_raw asserted during MAC state — delayed twice to get mac_en
// load_bias_raw asserted during LOAD — delayed once to get load_bias
// write_en_raw asserted during WRITE — delayed once to get write_en

always_comb begin
    load_bias_raw = (state == LOAD);
    mac_en_raw = (state == MAC);
    write_en_raw = (state == WRITE);
    done = (state == DONE);
end

// Stage-1 pipeline registers (1-cycle delay)

logic mac_en_p1;  // intermediate: 1-cycle delayed mac_en_raw

always_ff @(posedge clk) begin
    if (rst) begin
        load_bias <= 1'b0;
        mac_en_p1 <= 1'b0;
        write_en <= 1'b0;
    end
    else begin
        load_bias <= load_bias_raw;
        mac_en_p1 <= mac_en_raw;
        write_en <= write_en_raw;
    end
end

// Stage-2 pipeline register: mac_en is 2-cycle delayed from mac_en_raw

always_ff @(posedge clk) begin
    if (rst)
        mac_en <= 1'b0;
    else
        mac_en <= mac_en_p1;
end

// Stage-3 pipeline register: mac_en_d1 is 3-cycle delayed from mac_en_raw

always_ff @(posedge clk) begin
    if (rst)
        mac_en_d1 <= 1'b0;
    else
        mac_en_d1 <= mac_en;
end

endmodule
