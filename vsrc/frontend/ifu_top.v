// ============================================================
// ifu_top.v — 前端顶层（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来输出单条指令给 backend（ibuffer_instr_valid/ready + inst/pc）
//   改为同时输出 2 条指令给 backend 的双 decoder
//
// 改动内容：
//   1. 端口从单路改为双路（instr0_* 和 instr1_*）
//   2. ibuffer 例化改为新的双路接口
//   3. pc_ctrl, instr_admin, bpu 不变
// ============================================================

module ifu_top (
    input wire clock,
    input wire reset_n,

    // Inputs for PC control
    input  wire [`PC_RANGE] boot_addr,
    input  wire             interrupt_valid,
    input  wire [`PC_RANGE] interrupt_addr,
    input  wire             redirect_valid,
    input  wire [`PC_RANGE] redirect_target,
    output wire             pc_index_valid,
    input  wire             pc_index_ready,
    input  wire             pc_operation_done,

    // Inputs for instruction buffer
    input wire [`ICACHE_FETCHWIDTH128_RANGE] pc_read_inst,

    // --- [2-wide] 双路输出给 backend（原先是单路） ---
    // instr0: 第 1 条指令
    input  wire        ibuffer_instr0_ready,
    output wire        ibuffer_instr0_valid,
    output wire        ibuffer_predicttaken0_out,
    output wire [31:0] ibuffer_predicttarget0_out,
    output wire [31:0] ibuffer_inst0_out,
    output wire [63:0] ibuffer_pc0_out,

    // instr1: 第 2 条指令
    input  wire        ibuffer_instr1_ready,
    output wire        ibuffer_instr1_valid,
    output wire        ibuffer_predicttaken1_out,
    output wire [31:0] ibuffer_predicttarget1_out,
    output wire [31:0] ibuffer_inst1_out,
    output wire [63:0] ibuffer_pc1_out,

    output wire        fifo_empty,

    // Outputs from pc_ctrl
    output wire [63:0] pc_index,

    input wire       backend_stall,

    // BHT Write Interface
    input wire       bht_write_enable,
    input wire [8:0] bht_write_index,
    input wire [1:0] bht_write_counter_select,
    input wire       bht_write_inc,
    input wire       bht_write_dec,
    input wire       bht_valid_in,

    // BTB Write Interface
    input wire         btb_ce,
    input wire         btb_we,
    input wire [128:0] btb_wmask,
    input wire [  8:0] btb_write_index,
    input wire [128:0] btb_din,
    input  wire end_of_program
);

    // Internal signals
    wire fetch_inst;
    wire can_fetch_inst;
    wire [63:0] pc;

    /* --------------------------- bpu related signals -------------------------- */
    wire                               pc_req_handshake;
    wire [                        7:0] bht_read_data;
    wire                               bht_valid;
    wire [                       31:0] bht_read_miss_count;
    wire [                      127:0] btb_targets;
    wire                               btb_valid;
    wire [                       31:0] btb_read_miss_count;

    /* ----------------------------- admin output signal ---------------------------- */
    wire [`ICACHE_FETCHWIDTH128_RANGE] admin2ib_instr;
    wire [                        3:0] admin2ib_instr_valid;
    wire [                        3:0] admin2ib_predicttaken;
    wire [                   4*32-1:0] admin2ib_predicttarget;
    wire                               admin2pcctrl_predicttaken;
    wire [                       31:0] admin2pcctrl_predicttarget;

    // --- [2-wide] ibuffer 例化（双路输出） ---
    ibuffer ibuffer_inst (
        .clock                     (clock),
        .reset_n                   (reset_n),
        .pc                        (pc),
        .pc_index_ready            (pc_index_ready),
        .pc_operation_done         (pc_operation_done),
        .admin2ib_instr            (admin2ib_instr),
        .admin2ib_instr_valid      (admin2ib_instr_valid),
        .redirect_valid            (redirect_valid),
        .fetch_inst                (fetch_inst),
        .backend_stall             (backend_stall),
        .admin2ib_predicttaken     (admin2ib_predicttaken),
        .admin2ib_predicttarget    (admin2ib_predicttarget),

        // [2-wide] 双路输出（原先是单路 ibuffer_instr_valid/ready/inst_out/pc_out）
        .ibuffer_instr0_ready      (ibuffer_instr0_ready),
        .ibuffer_instr0_valid      (ibuffer_instr0_valid),
        .ibuffer_predicttaken0_out (ibuffer_predicttaken0_out),
        .ibuffer_predicttarget0_out(ibuffer_predicttarget0_out),
        .ibuffer_inst0_out         (ibuffer_inst0_out),
        .ibuffer_pc0_out           (ibuffer_pc0_out),

        .ibuffer_instr1_ready      (ibuffer_instr1_ready),
        .ibuffer_instr1_valid      (ibuffer_instr1_valid),
        .ibuffer_predicttaken1_out (ibuffer_predicttaken1_out),
        .ibuffer_predicttarget1_out(ibuffer_predicttarget1_out),
        .ibuffer_inst1_out         (ibuffer_inst1_out),
        .ibuffer_pc1_out           (ibuffer_pc1_out),

        .fifo_empty                (fifo_empty)
    );

    // instr_admin — 零改动（不涉及 2-wide）
    instr_admin u_instr_admin (
        .pc_operation_done         (pc_operation_done),
        .fetch_instr               (pc_read_inst),
        .pc                        (pc),
        .admin2ib_instr            (admin2ib_instr),
        .admin2ib_instr_valid      (admin2ib_instr_valid),
        .bht_read_data             (bht_read_data),
        .bht_valid                 (bht_valid),
        .btb_targets               (btb_targets),
        .btb_valid                 (btb_valid),
        .admin2ib_predicttaken     (admin2ib_predicttaken),
        .admin2ib_predicttarget    (admin2ib_predicttarget),
        .admin2pcctrl_predicttaken (admin2pcctrl_predicttaken),
        .admin2pcctrl_predicttarget(admin2pcctrl_predicttarget)
    );

    // pc_ctrl — 零改动
    pc_ctrl pc_ctrl_inst (
        .clock                     (clock),
        .reset_n                   (reset_n),
        .pc                        (pc),
        .boot_addr                 (boot_addr),
        .redirect_valid            (redirect_valid),
        .redirect_target           (redirect_target),
        .fetch_inst                (fetch_inst),
        .pc_index_valid            (pc_index_valid),
        .pc_index                  (pc_index),
        .pc_index_ready            (pc_index_ready),
        .pc_operation_done         (pc_operation_done),
        .admin2pcctrl_predicttaken (admin2pcctrl_predicttaken),
        .admin2pcctrl_predicttarget(admin2pcctrl_predicttarget),
        .pc_req_handshake          (pc_req_handshake)
    );

    // bpu — 零改动
    bpu u_bpu (
        .clock                   (clock),
        .reset_n                 (reset_n),
        .pc                      (pc),
        .bht_write_enable        (bht_write_enable),
        .bht_write_index         (bht_write_index),
        .bht_write_counter_select(bht_write_counter_select),
        .bht_write_inc           (bht_write_inc),
        .bht_write_dec           (bht_write_dec),
        .bht_valid_in            (bht_valid_in),
        .btb_ce                  (pc_req_handshake || btb_ce),
        .btb_we                  (btb_we),
        .btb_wmask               (btb_wmask),
        .btb_write_index         (btb_write_index),
        .btb_din                 (btb_din),
        .bht_read_enable         (pc_req_handshake),
        .bht_read_data           (bht_read_data),
        .bht_valid               (bht_valid),
        .bht_read_miss_count     (bht_read_miss_count),
        .btb_targets             (btb_targets),
        .btb_valid               (btb_valid),
        .btb_read_miss_count     (btb_read_miss_count)
    );

endmodule
