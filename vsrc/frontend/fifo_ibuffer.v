// ============================================================
// fifo_ibuffer.v — 双端口组合读 FIFO（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来是单路寄存器输出（read_en 时钟沿锁存到 data_out）
//   改为双路组合读 + consume 语义
//
// 改动原因：
//   1. 支持每周期弹出 2 条指令（2-wide decode/dispatch）
//   2. 组合读避免"弹出后下游拒收导致数据丢失"的问题
//   3. consume 语义：下游确认消费后才前进 read_ptr
//
// FIFO 深度从 48 改为 64（2的幂，方便 mask 运算）
// ============================================================

module fifo_ibuffer (
    input  wire        clock,
    input  wire        reset_n,
    input  wire [128:0] data_in,        // 写入数据：{predict_taken, predict_target[31:0], inst[31:0], pc[63:0]}
    input  wire        write_en,        // 写使能
    input  wire        redirect_valid,  // 重定向（分支误预测等），清空 FIFO
    input  wire        stall,           // 全局后端 stall

    // --- [2-wide] 双路组合读输出 ---
    // 改动原因：原来只有 1 个 data_out + data_valid + read_en
    // 现在需要同时输出 2 条指令给双 decoder
    output wire [128:0] data_out_0,     // 位置 0 的指令（组合逻辑，零延迟）
    output wire [128:0] data_out_1,     // 位置 1 的指令（组合逻辑，零延迟）
    output wire         data_valid_0,   // count >= 1，至少有 1 条可读
    output wire         data_valid_1,   // count >= 2，至少有 2 条可读
    output wire         empty,          // FIFO 为空
    output wire         almost_empty,   // count == 1，只有 1 条（双弹出会退化）
    output wire         full,           // FIFO 已满
    output wire  [5:0]  count,          // 当前 FIFO 中的指令数量

    // --- [2-wide] consume 信号（替代原来的 read_en） ---
    // consume 语义：下游真正消费了才前进 read_ptr
    // consume_0：消费位置 0 的指令（可以独立消费）
    // consume_1：消费位置 1 的指令（保序：必须在 consume_0=1 时才有效）
    input  wire        consume_0,
    input  wire        consume_1
);

    // --- [2-wide] 深度从 48 改为 64（2的幂） ---
    // 原因：48 不是 2 的幂，取模 % 48 综合效率低
    // 64 可以用 & 6'h3F 代替取模
    localparam FIFO_DEPTH = 64;
    localparam FIFO_DEPTH_LOG = 6;
    localparam FIFO_MASK = 6'h3F;   // 64 - 1

    reg [128:0] fifo [0:FIFO_DEPTH-1];   // FIFO 存储
    reg [FIFO_DEPTH_LOG-1:0] read_ptr;   // 读指针
    reg [FIFO_DEPTH_LOG-1:0] write_ptr;  // 写指针
    reg [FIFO_DEPTH_LOG:0]   count_ext;  // 7 bit 计数器，最大 64

    // --- 输出信号 ---
    assign count        = count_ext[FIFO_DEPTH_LOG-1:0];
    assign empty        = (count_ext == 7'd0);
    assign almost_empty = (count_ext == 7'd1);  // [2-wide] 新增：只剩1条，双弹出会退化
    assign full         = (count_ext == 7'd64);

    // --- [2-wide] 组合逻辑读（关键路径） ---
    // 注意：这会增加关键路径（SRAM read -> decoder -> pipereg）
    // 但省掉 1 周期延迟，吞吐量更好。Trinity 频率不高，可以接受。
    assign data_out_0   = fifo[read_ptr];
    assign data_out_1   = fifo[(read_ptr + 6'd1) & FIFO_MASK];
    assign data_valid_0 = !empty;
    assign data_valid_1 = !empty && !almost_empty;  // 需要至少 2 条才输出 valid_1

    // --- [2-wide] 保序 consume 逻辑 ---
    // actual_consume_1 要求 consume_0 也为 1
    // 这保证了不会跳过 instr0 先消费 instr1（保序铁律）
    // stall 时所有 consume 被屏蔽
    wire actual_consume_0 = consume_0 && !stall && !empty;
    wire actual_consume_1 = consume_1 && consume_0 && !stall && !almost_empty && !empty;
    // 注意：actual_consume_1 要求 !almost_empty（只有1条时不能消费第2条）

    // --- 写入逻辑 ---
    wire actual_write = write_en && !full;

    // --- [2-wide] read_ptr 更新（保序消费） ---
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            read_ptr <= 6'b0;
        end else begin
            case ({actual_consume_0, actual_consume_1})
                2'b11:   read_ptr <= (read_ptr + 6'd2) & FIFO_MASK;  // 双消费，前进 2
                2'b10:   read_ptr <= (read_ptr + 6'd1) & FIFO_MASK;  // 单消费，前进 1
                default: ;  // 不消费，read_ptr 不动
            endcase
        end
    end

    // --- write_ptr 更新 ---
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            write_ptr <= 6'b0;
        end else if (actual_write) begin
            write_ptr <= (write_ptr + 6'd1) & FIFO_MASK;
        end
    end

    // --- [2-wide] count 更新（双增双减） ---
    // 根据 write 和 consume 的组合更新 count
    // 用 if-else if 链避免 case 综合产生 latch
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n || redirect_valid) begin
            count_ext <= 7'b0;
        end else begin
            if (actual_write && actual_consume_0 && actual_consume_1) begin
                // 写 1 + 消费 2 = net -1
                count_ext <= count_ext - 7'd1;
            end else if (actual_write && actual_consume_0 && !actual_consume_1) begin
                // 写 1 + 消费 1 = net 0
                count_ext <= count_ext;
            end else if (actual_write && !actual_consume_0) begin
                // 写 1 + 消费 0 = net +1
                count_ext <= count_ext + 7'd1;
            end else if (!actual_write && actual_consume_0 && actual_consume_1) begin
                // 写 0 + 消费 2 = net -2
                count_ext <= count_ext - 7'd2;
            end else if (!actual_write && actual_consume_0 && !actual_consume_1) begin
                // 写 0 + 消费 1 = net -1
                count_ext <= count_ext - 7'd1;
            end
            // else: 无写无消费，count 不变
        end
    end

    // --- 数据写入 ---
    always @(posedge clock) begin
        if (actual_write) begin
            fifo[write_ptr] <= data_in;
        end
    end

endmodule
