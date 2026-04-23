module ibuffer (
    input wire                               clock,
    input wire                               reset_n,
    input wire                               pc_index_ready,          // Signal indicating readiness from `pc_index`
    input wire                               pc_operation_done,
    input wire [`ICACHE_FETCHWIDTH128_RANGE] admin2ib_instr,          // 64-bit input data from arbiter (two instructions, 32 bits each)
    input wire [                        3:0] admin2ib_instr_valid,    // 2-bit validity indicator (11 or 01)
    input wire [                        3:0] admin2ib_predicttaken,
    input wire [                   4*32-1:0] admin2ib_predicttarget,
    input wire                               redirect_valid,          // Clear signal for ibuffer
    input wire [                       63:0] pc,

    input  wire             ibuffer_instr_ready,        // External read enable signal for FIFO
    output wire             ibuffer_instr_valid,
    output wire             ibuffer_predicttaken_out,
    output wire [     31:0] ibuffer_predicttarget_out,
    output wire [     31:0] ibuffer_inst_out,
    output wire [`PC_RANGE] ibuffer_pc_out,
    output reg              fetch_inst,                 // Output pulse when FIFO count decreases from 4 to 3
    output wire             fifo_empty,                 // Signal indicating if the FIFO is empty

    input wire backend_stall
);

    reg [1:0] front_zero_cnt;  //0,1,2,3
    always @(*) begin
        integer i;
        front_zero_cnt = 'b0;
        for (i = 0; i < 4; i = i + 1) begin
            if (admin2ib_instr_valid[i] == 1'b0) begin
                front_zero_cnt = front_zero_cnt + 'b1;
            end else begin
                break;
            end
        end
    end

    wire [`ICACHE_FETCHWIDTH128_RANGE] shift_admin2ib_instr;
    wire [                        3:0] shift_admin2ib_instr_valid;
    wire [                        3:0] shift_admin2ib_predicttaken;
    wire [                   4*32-1:0] shift_admin2ib_predicttarget;

    assign shift_admin2ib_instr       = admin2ib_instr >> (32 * front_zero_cnt);
    assign shift_admin2ib_instr_valid = admin2ib_instr_valid >> (front_zero_cnt);
    assign shift_admin2ib_predicttaken = admin2ib_predicttaken >> (front_zero_cnt);
    assign shift_admin2ib_predicttarget = admin2ib_predicttarget >> (32 * front_zero_cnt);


    wire [(1+32+32+64-1):0] fifo_data_out;  // Output data from the FIFO
    assign ibuffer_predicttaken_out  = fifo_data_out[(1+32+64+32-1) : (32+64+32)];
    assign ibuffer_predicttarget_out = fifo_data_out[(32+64+32-1) : (32+64)];
    assign ibuffer_inst_out          = fifo_data_out[(32+64-1):64];
    assign ibuffer_pc_out            = fifo_data_out[`PC_RANGE];

    // Internal buffers for splitting instructions
    reg [31:0] inst_cut          [0:3];
    reg [63:0] pc_cut            [0:3];
    reg        predict_taken_cut [0:3];
    reg [31:0] predict_target_cut[0:3];

    // Splitting instructions and calculating PCs
    always @(*) begin
        inst_cut[0]           = shift_admin2ib_instr[31:0];
        inst_cut[1]           = shift_admin2ib_instr[63:32];
        inst_cut[2]           = shift_admin2ib_instr[95:64];
        inst_cut[3]           = shift_admin2ib_instr[127:96];
        pc_cut[0]             = pc;
        pc_cut[1]             = pc + 4;
        pc_cut[2]             = pc + 8;
        pc_cut[3]             = pc + 12;
        predict_taken_cut[0]  = shift_admin2ib_predicttaken[0];
        predict_taken_cut[1]  = shift_admin2ib_predicttaken[1];
        predict_taken_cut[2]  = shift_admin2ib_predicttaken[2];
        predict_taken_cut[3]  = shift_admin2ib_predicttaken[3];
        predict_target_cut[0] = shift_admin2ib_predicttarget[31:0];
        predict_target_cut[1] = shift_admin2ib_predicttarget[63:32];
        predict_target_cut[2] = shift_admin2ib_predicttarget[95:64];
        predict_target_cut[3] = shift_admin2ib_predicttarget[127:96];
    end

    // FIFO signals
    reg  [(1+32+32+64-1):0] inst_buffer                                                                         [0:3];  // Buffer for up to 4 instructions, 32bit instr+64bit addr
    wire                    fifo_full;  // Full signal from FIFO
    wire [             5:0] fifo_count;  // Count of entries in the FIFO
    reg  [             5:0] fifo_count_prev;  // Previous FIFO count to detect transition from 4 to 3
    reg  [             2:0] valid_counter;  // Counter for valid instructions //3bit becouse max valid_counter=4
    reg  [             2:0] write_index;  // Index for writing to FIFO
    // Instantiate the FIFO
    fifo_ibuffer fifo_inst (
        .clock         (clock),
        .reset_n       (reset_n),
        .data_in       (inst_buffer[write_index]),  // Input to FIFO
        .write_en      (valid_counter > 0),         // Write enable based on counter
        .read_en       (ibuffer_instr_ready),
        .redirect_valid(redirect_valid),            // Pass clear signal to FIFO
        .data_out      (fifo_data_out),
        .empty         (fifo_empty),
        .full          (fifo_full),
        .count         (fifo_count),
        .data_valid    (ibuffer_instr_valid),
        .stall         (backend_stall)
    );

    // Control logic for writing instructions to FIFO
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            fetch_inst      <= 1'b1;
            fifo_count_prev <= 6'b0;
        end else begin
            // Generate inst_buffer  based on shift_admin2ib_instr_valid
            if (shift_admin2ib_instr_valid[0]) begin
                inst_buffer[0] <= {predict_taken_cut[0], predict_target_cut[0][31:0], inst_cut[0], pc_cut[0][63:0]};
            end

            if (shift_admin2ib_instr_valid[1]) begin
                inst_buffer[1] <= {predict_taken_cut[1], predict_target_cut[1][31:0], inst_cut[1], pc_cut[1][63:0]};
            end

            if (shift_admin2ib_instr_valid[2]) begin
                inst_buffer[2] <= {predict_taken_cut[2], predict_target_cut[2][31:0], inst_cut[2], pc_cut[2][63:0]};
            end

            if (shift_admin2ib_instr_valid[3]) begin
                inst_buffer[3] <= {predict_taken_cut[3], predict_target_cut[3][31:0], inst_cut[3], pc_cut[3][63:0]};
            end

            // Update fifo_count_prev to detect transition from 4 to 3
            fifo_count_prev <= fifo_count;

            // Generate fetch_inst pulse when FIFO count decreases from 4 to 3
            fetch_inst      <= ((fifo_count_prev == 6'd4 && fifo_count == 6'd3) || fifo_empty) ? 1'b1 : 1'b0;
        end
    end
    // Control logic for writing instructions to FIFO
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            valid_counter <= 3'h0;
        end else begin
            // Initialize valid_counter based on shift_admin2ib_instr_valid
            if (shift_admin2ib_instr_valid != 4'b0000) begin
                valid_counter <= shift_admin2ib_instr_valid[0] + shift_admin2ib_instr_valid[1] + shift_admin2ib_instr_valid[2] + shift_admin2ib_instr_valid[3];
            end  // Write instructions to FIFO and decrement counter
            else if (valid_counter > 0 && !fifo_full) begin
                valid_counter <= valid_counter - 1;
            end
        end
    end
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            write_index <= 'b0;
        end else begin
            if (valid_counter > 0 & ~fifo_full) begin
                write_index <= write_index + 3'h1;
            end else if (valid_counter == 0) begin
                write_index <= 'b0;
            end
        end
    end
endmodule
