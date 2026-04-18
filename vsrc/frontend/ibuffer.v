// ============================================================
// ibuffer.v — 双路输出指令缓冲（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来输出单条指令给 decoder（ibuffer_instr_valid/ready + inst/pc）
//   改为同时输出 2 条指令给双 decoder
//
// 改动内容：
//   1. 输出端口从单路改为双路（instr0_* 和 instr1_*）
//   2. FIFO 例化改为新的双路接口（data_out_0/1, consume_0/1）
//   3. consume 保序逻辑：consume_1 依赖 consume_0
//   4. 写入路径（inst_buffer, valid_counter, write_index）不变
//
// 不改的部分：
//   - inst_buffer / 写入逻辑（每周期从 icache 收最多 4 条指令，逐条写 FIFO）
//   - fetch_inst 生成逻辑（FIFO 计数变化时触发 fetch）
//   - front_zero_cnt 消前导无效指令的逻辑
// ============================================================

module ibuffer (
    input wire                               clock,
    input wire                               reset_n,
    input wire                               pc_index_ready,
    input wire                               pc_operation_done,
    input wire [`ICACHE_FETCHWIDTH128_RANGE] admin2ib_instr,          // 128-bit input (4 instructions)
    input wire [                        3:0] admin2ib_instr_valid,    // 4-bit validity
    input wire [                        3:0] admin2ib_predicttaken,
    input wire [                   4*32-1:0] admin2ib_predicttarget,
    input wire                               redirect_valid,
    input wire [                       63:0] pc,

    // --- [2-wide] 双路输出端口（原先是单路） ---
    // instr0: 第 1 条指令（可以独立 valid/ready）
    input  wire             ibuffer_instr0_ready,       // 下游 decoder0 准备好接收
    output wire             ibuffer_instr0_valid,       // FIFO 有至少 1 条可读
    output wire             ibuffer_predicttaken0_out,
    output wire [     31:0] ibuffer_predicttarget0_out,
    output wire [     31:0] ibuffer_inst0_out,
    output wire [`PC_RANGE] ibuffer_pc0_out,

    // instr1: 第 2 条指令（保序：必须在 instr0 也被消费时才有效）
    input  wire             ibuffer_instr1_ready,       // 下游 decoder1 准备好接收
    output wire             ibuffer_instr1_valid,       // FIFO 有至少 2 条可读
    output wire             ibuffer_predicttaken1_out,
    output wire [     31:0] ibuffer_predicttarget1_out,
    output wire [     31:0] ibuffer_inst1_out,
    output wire [`PC_RANGE] ibuffer_pc1_out,

    output reg              fetch_inst,                 // FIFO count 4→3 时触发 fetch
    output wire             fifo_empty,

    input wire backend_stall
);

    // --- [2-wide] 消前导无效指令（原始逻辑，不改动） ---
    reg [1:0] front_zero_cnt;
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

    assign shift_admin2ib_instr        = admin2ib_instr >> (32 * front_zero_cnt);
    assign shift_admin2ib_instr_valid  = admin2ib_instr_valid >> (front_zero_cnt);
    assign shift_admin2ib_predicttaken = admin2ib_predicttaken >> (front_zero_cnt);
    assign shift_admin2ib_predicttarget = admin2ib_predicttarget >> (32 * front_zero_cnt);

    // --- [2-wide] 双路 FIFO 输出数据拆包 ---
    // fifo_data_out_0: FIFO 位置 0 的数据（组合逻辑读）
    // fifo_data_out_1: FIFO 位置 1 的数据（组合逻辑读）
    // 数据格式: {predict_taken[1bit], predict_target[32bit], inst[32bit], pc[64bit]} = 129 bit
    wire [(1+32+32+64-1):0] fifo_data_out_0;
    wire [(1+32+32+64-1):0] fifo_data_out_1;

    // --- [2-wide] instr0 拆包（位置 0） ---
    assign ibuffer_predicttaken0_out  = fifo_data_out_0[(1+32+64+32-1) : (32+64+32)];
    assign ibuffer_predicttarget0_out = fifo_data_out_0[(32+64+32-1) : (32+64)];
    assign ibuffer_inst0_out          = fifo_data_out_0[(32+64-1):64];
    assign ibuffer_pc0_out            = fifo_data_out_0[`PC_RANGE];

    // --- [2-wide] instr1 拆包（位置 1） ---
    assign ibuffer_predicttaken1_out  = fifo_data_out_1[(1+32+64+32-1) : (32+64+32)];
    assign ibuffer_predicttarget1_out = fifo_data_out_1[(32+64+32-1) : (32+64)];
    assign ibuffer_inst1_out          = fifo_data_out_1[(32+64-1):64];
    assign ibuffer_pc1_out            = fifo_data_out_1[`PC_RANGE];

    // --- [2-wide] FIFO 状态信号 ---
    wire fifo_full;
    wire fifo_almost_empty;
    wire [5:0] fifo_count;

    // --- [2-wide] consume 保序逻辑 ---
    // consume_0：下游 decoder0 准备好 + FIFO 非空 → 消费位置 0
    // consume_1：下游 decoder0 和 decoder1 都准备好 + FIFO 至少有 2 条 → 消费位置 1
    // 保序铁律：consume_1 依赖 consume_0（即 instr0_ready），
    //           不会出现跳过 instr0 先消费 instr1 的情况
    wire consume_0 = ibuffer_instr0_ready;
    wire consume_1 = ibuffer_instr0_ready && ibuffer_instr1_ready;

    // --- [2-wide] FIFO 例化（新接口：双路组合读 + consume 语义） ---
    // 改动原因：原来用 read_en（时钟沿锁存）+ data_out（单路寄存器输出）
    // 现在用 consume_0/1（下游确认消费后才前进 read_ptr）+ data_out_0/1（双路组合读）
    fifo_ibuffer fifo_inst (
        .clock         (clock),
        .reset_n       (reset_n),
        .data_in       (inst_buffer[write_index]),
        .write_en      (valid_counter > 0),
        .redirect_valid(redirect_valid),
        .stall         (backend_stall),

        // [2-wide] 双路输出
        .data_out_0    (fifo_data_out_0),
        .data_out_1    (fifo_data_out_1),
        .data_valid_0  (ibuffer_instr0_valid),
        .data_valid_1  (ibuffer_instr1_valid),
        .empty         (fifo_empty),
        .almost_empty  (fifo_almost_empty),
        .full          (fifo_full),
        .count         (fifo_count),

        // [2-wide] consume 信号
        .consume_0     (consume_0),
        .consume_1     (consume_1)
    );

    // --- 写入路径（原始逻辑，不改动） ---
    // inst_buffer: 4 个 129-bit 寄存器，暂存从 instr_admin 来的指令
    // valid_counter: 剩余待写入 FIFO 的指令数
    // write_index: 当前写入 FIFO 的 inst_buffer 索引
    reg [(1+32+32+64-1):0] inst_buffer [0:3];
    reg  [             5:0] fifo_count_prev;
    reg  [             2:0] valid_counter;
    reg  [             2:0] write_index;

    reg [31:0] inst_cut          [0:3];
    reg [63:0] pc_cut            [0:3];
    reg        predict_taken_cut [0:3];
    reg [31:0] predict_target_cut[0:3];

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

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            fetch_inst      <= 1'b1;
            fifo_count_prev <= 6'b0;
        end else begin
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
            fifo_count_prev <= fifo_count;
            fetch_inst      <= ((fifo_count_prev == 6'd4 && fifo_count == 6'd3) || fifo_empty) ? 1'b1 : 1'b0;
        end
    end

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            valid_counter <= 3'h0;
        end else begin
            if (shift_admin2ib_instr_valid != 4'b0000) begin
                valid_counter <= shift_admin2ib_instr_valid[0] + shift_admin2ib_instr_valid[1] + shift_admin2ib_instr_valid[2] + shift_admin2ib_instr_valid[3];
            end else if (valid_counter > 0 && !fifo_full) begin
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
