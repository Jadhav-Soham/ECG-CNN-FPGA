module conv1d_controller #(
parameter IN_CHANNELS  = 32,
parameter OUT_CHANNELS = 64,
parameter OUT_LENGTH   = 32,
parameter KERNEL_SIZE  = 5,
parameter PAR_OUT      = 16
)(
input logic clk,
input logic rst,
input logic start,

output logic load_bias,
output logic mac_en,
output logic write_en,
output logic done,

output logic [$clog2(OUT_LENGTH)-1:0] pos_cnt,
output logic [$clog2(IN_CHANNELS)-1:0] ch_cnt,
output logic [$clog2(KERNEL_SIZE)-1:0] tap_cnt,
output logic [$clog2(OUT_CHANNELS/PAR_OUT)-1:0] grp_cnt
);

// FSM STATES
localparam IDLE=0,
           LOAD=1,
           MAC =2,
           WRITE=3,
           NEXT=4,
           DONE=5;

logic [2:0] state;

// FSM
always_ff @(posedge clk) begin

    if(rst) begin
        state<=IDLE;
        pos_cnt<=0;
        grp_cnt<=0;
        ch_cnt<=0;
        tap_cnt<=0;
    end

    else begin

        case(state)

        IDLE:
            if(start) state<=LOAD;
        
        LOAD: begin
            ch_cnt<=0;
            tap_cnt<=0;
            state<=MAC;
        end

        MAC: begin

            if(tap_cnt<KERNEL_SIZE-1)begin
                tap_cnt<=tap_cnt+1;
                state <= MAC;
            end   
            
            else begin
                tap_cnt<=0;

                if(ch_cnt<IN_CHANNELS-1)begin
                    ch_cnt<=ch_cnt+1;
                    state <= MAC;
                end
                else
                    state<=WRITE;
            end
        end

        WRITE: begin
            
            if(grp_cnt<(OUT_CHANNELS/PAR_OUT)-1) begin
                grp_cnt<=grp_cnt+1;
                state<=LOAD;
            end
            else begin
                grp_cnt<=0;
                state<=NEXT;
            end
        end

        NEXT: begin
            
            if(pos_cnt<OUT_LENGTH-1) begin
                pos_cnt<=pos_cnt+1;
                state<=LOAD;
            end
            else
                state<=DONE;
        end

        DONE: 
            state<=IDLE;

        endcase
    end
end

always_comb begin
    load_bias = (state == LOAD);
    mac_en    = (state == MAC);
    write_en  = (state == WRITE);
    done      = (state == DONE);
end

endmodule