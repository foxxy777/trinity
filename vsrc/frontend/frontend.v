// ============================================================
// frontend.v — 前端顶层 wrapper（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来单路 ibuffer_instr_valid/ready/inst_out/pc_out
//   改为双路 instr0_* 和 instr1_*
//
// backend_stall 逻辑改动：
//   原来：~ibuffer_instr_ready（单个 ready 取反）
//   现在：~ibuffer_instr0_ready（只要 instr0 不 ready 就 stall 整个前端）
//   原因：保序铁律——instr0 必须先走，instr0 被卡时前端不应继续弹出
// ============================================================

module frontend (
    input wire clock,
    input wire reset_n,

    // PC control
    input wire             redirect_valid,
    input wire [`PC_RANGE] redirect_target,

    output wire                               pc_index_valid,
    input  wire                               pc_index_ready,
    input  wire                               pc_operation_done,
    input  wire [`ICACHE_FETCHWIDTH128_RANGE] pc_read_inst,
    output wire [                       63:0] pc_index,

    // --- [2-wide] 双路指令输出（原先是单路） ---
    // instr0: 第 1 条指令
    input  wire        ibuffer_instr0_ready,
    output wire        ibuffer_instr0_valid,
    output wire [31:0] ibuffer_inst0_out,
    output wire [63:0] ibuffer_pc0_out,
    output wire        ibuffer_predicttaken0_out,
    output wire [31:0] ibuffer_predicttarget0_out,

    // instr1: 第 2 条指令
    input  wire        ibuffer_instr1_ready,
    output wire        ibuffer_instr1_valid,
    output wire [31:0] ibuffer_inst1_out,
    output wire [63:0] ibuffer_pc1_out,
    output wire        ibuffer_predicttaken1_out,
    output wire [31:0] ibuffer_predicttarget1_out,

    // BHT Write Interface
    input wire       intwb_bht_write_enable,
    input wire [8:0] intwb_bht_write_index,
    input wire [1:0] intwb_bht_write_counter_select,
    input wire       intwb_bht_write_inc,
    input wire       intwb_bht_write_dec,
    input wire       intwb_bht_valid_in,

    // BTB Write Interface
    input wire         intwb_btb_ce,
    input wire         intwb_btb_we,
    input wire [128:0] intwb_btb_wmask,
    input wire [  8:0] intwb_btb_write_index,
    input wire [128:0] intwb_btb_din,
    input wire         end_of_program
);

    // --- [2-wide] backend_stall 逻辑 ---
    // 原来：wire backend_stall = ~ibuffer_instr_ready;
    // 现在：只要 instr0 不 ready 就 stall（保序，instr0 是前置条件）
    wire backend_stall = ~ibuffer_instr0_ready;
    wire fifo_empty;

    ifu_top u_ifu_top (
        .clock                    (clock),
        .reset_n                  (reset_n),
        .boot_addr                (64'h80000000),
        .interrupt_valid          (1'd0),
        .interrupt_addr           (64'd0),
        .redirect_valid           (redirect_valid),
        .redirect_target          (redirect_target),
        .pc_index_valid           (pc_index_valid),
        .pc_index_ready           (pc_index_ready),
        .pc_operation_done        (pc_operation_done),
        .pc_read_inst             (pc_read_inst),
        .pc_index                 (pc_index),
        .fifo_empty               (fifo_empty),
        .backend_stall            (backend_stall),

        // [2-wide] 双路信号
        .ibuffer_instr0_ready      (ibuffer_instr0_ready),
        .ibuffer_instr0_valid      (ibuffer_instr0_valid),
        .ibuffer_inst0_out         (ibuffer_inst0_out),
        .ibuffer_pc0_out           (ibuffer_pc0_out),
        .ibuffer_predicttaken0_out (ibuffer_predicttaken0_out),
        .ibuffer_predicttarget0_out(ibuffer_predicttarget0_out),

        .ibuffer_instr1_ready      (ibuffer_instr1_ready),
        .ibuffer_instr1_valid      (ibuffer_instr1_valid),
        .ibuffer_inst1_out         (ibuffer_inst1_out),
        .ibuffer_pc1_out           (ibuffer_pc1_out),
        .ibuffer_predicttaken1_out (ibuffer_predicttaken1_out),
        .ibuffer_predicttarget1_out(ibuffer_predicttarget1_out),

        // BHT/BTB signals
        .bht_write_enable         (intwb_bht_write_enable),
        .bht_write_index          (intwb_bht_write_index),
        .bht_write_counter_select (intwb_bht_write_counter_select),
        .bht_write_inc            (intwb_bht_write_inc),
        .bht_write_dec            (intwb_bht_write_dec),
        .bht_valid_in             (intwb_bht_valid_in),
        .btb_ce                   (intwb_btb_ce),
        .btb_we                   (intwb_btb_we),
        .btb_wmask                (intwb_btb_wmask),
        .btb_write_index          (intwb_btb_write_index),
        .btb_din                  (intwb_btb_din),
        .end_of_program           (end_of_program)
    );

endmodule
