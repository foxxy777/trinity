`include "defines.sv"
// ============================================================
// core_top.sv — CPU 顶层（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来 frontend 和 backend 之间是单路 ibuffer 信号
//   改为双路 instr0_* 和 instr1_*
//
// 改动内容：
//   1. wire 声明：6 根单路 → 12 根双路
//   2. frontend 例化：双路端口
//   3. backend 例化：双路端口（新增 instr1_*）
// ============================================================

module core_top #(
    parameter BHTBTB_INDEX_WIDTH = 9
) (
    input wire clock,
    input wire reset_n,

    // DDR Control
    output wire         ddr_chip_enable,
    output wire [ 63:0] ddr_index,
    output wire         ddr_write_enable,
    output wire         ddr_burst_mode,
    output wire [511:0] ddr_write_data,
    input  wire [511:0] ddr_read_data,
    input  wire         ddr_operation_done,
    input  wire         ddr_ready
);
    wire                               arb2dcache_flush_valid;

    // --- [2-wide] 双路 ibuffer 信号（原来是 6 根单路） ---
    // 原来：
    //   wire ibuffer_instr_valid;
    //   wire ibuffer_instr_ready;
    //   wire [31:0] ibuffer_inst_out;
    //   wire [63:0] ibuffer_pc_out;
    //   wire ibuffer_predicttaken_out;
    //   wire [31:0] ibuffer_predicttarget_out;
    // 改为：
    wire                               ibuffer_instr0_valid;
    wire                               ibuffer_instr0_ready;
    wire [                       31:0] ibuffer_inst0_out;
    wire [                       63:0] ibuffer_pc0_out;
    wire                               ibuffer_predicttaken0_out;
    wire [                       31:0] ibuffer_predicttarget0_out;

    wire                               ibuffer_instr1_valid;
    wire                               ibuffer_instr1_ready;
    wire [                       31:0] ibuffer_inst1_out;
    wire [                       63:0] ibuffer_pc1_out;
    wire                               ibuffer_predicttaken1_out;
    wire [                       31:0] ibuffer_predicttarget1_out;

    // bht/btb write interface
    wire                               intwb_bht_write_enable;
    wire [     BHTBTB_INDEX_WIDTH-1:0] intwb_bht_write_index;
    wire [                        1:0] intwb_bht_write_counter_select;
    wire                               intwb_bht_write_inc;
    wire                               intwb_bht_write_dec;
    wire                               intwb_bht_valid_in;
    wire                               intwb_btb_ce;
    wire                               intwb_btb_we;
    wire [                      128:0] intwb_btb_wmask;
    wire [                        8:0] intwb_btb_write_index;
    wire [                      128:0] intwb_btb_din;

    // redirect
    wire                               flush_valid;
    wire [                  `PC_RANGE] flush_target;

    // PC Channel
    wire                               pc_index_valid;
    wire [                       63:0] pc_index;
    wire                               pc_index_ready;
    wire [`ICACHE_FETCHWIDTH128_RANGE] pc_read_inst;
    wire                               pc_operation_done;

    // tbus
    wire                               tbus_index_valid;
    wire                               tbus_index_ready;
    wire [              `RESULT_RANGE] tbus_index;
    wire [                 `SRC_RANGE] tbus_write_data;
    wire [                       63:0] tbus_write_mask;
    wire [              `RESULT_RANGE] tbus_read_data;
    wire [         `TBUS_OPTYPE_RANGE] tbus_operation_type;
    wire                               tbus_operation_done;

    reg                                dcache2arb_dbus_index_valid;
    wire                               dcache2arb_dbus_index_ready;
    reg  [              `RESULT_RANGE] dcache2arb_dbus_index;
    reg  [        `CACHELINE512_RANGE] dcache2arb_dbus_write_data;
    wire [        `CACHELINE512_RANGE] dcache2arb_dbus_read_data;
    wire                               dcache2arb_dbus_operation_done;
    wire [         `TBUS_OPTYPE_RANGE] dcache2arb_dbus_operation_type;
    wire                               dcache2arb_dbus_burst_mode;

    reg                                icache2arb_dbus_index_valid;
    wire                               icache2arb_dbus_index_ready;
    reg  [              `RESULT_RANGE] icache2arb_dbus_index;
    reg  [        `CACHELINE512_RANGE] icache2arb_dbus_write_data;
    reg  [                 `SRC_RANGE] icache2arb_dbus_write_mask;
    wire [        `CACHELINE512_RANGE] icache2arb_dbus_read_data;
    wire                               icache2arb_dbus_operation_done;
    wire [         `TBUS_OPTYPE_RANGE] icache2arb_dbus_operation_type;
    wire                               icache2arb_dbus_burst_mode;

    wire end_of_program;

    /* -------------------------------------------------------------------------- */
    /*                             channel_arb / icache / dcache                  */
    /* -------------------------------------------------------------------------- */
    channel_arb u_channel_arb (
        .clock                         (clock),
        .reset_n                       (reset_n),
        .icache2arb_dbus_index_valid   (icache2arb_dbus_index_valid),
        .icache2arb_dbus_index         (icache2arb_dbus_index),
        .icache2arb_dbus_index_ready   (icache2arb_dbus_index_ready),
        .icache2arb_dbus_read_data     (icache2arb_dbus_read_data),
        .icache2arb_dbus_operation_done(icache2arb_dbus_operation_done),
        .dcache2arb_dbus_index_valid   (dcache2arb_dbus_index_valid),
        .dcache2arb_dbus_index_ready   (dcache2arb_dbus_index_ready),
        .dcache2arb_dbus_index         (dcache2arb_dbus_index),
        .dcache2arb_dbus_write_data    (dcache2arb_dbus_write_data),
        .dcache2arb_dbus_read_data     (dcache2arb_dbus_read_data),
        .dcache2arb_dbus_operation_done(dcache2arb_dbus_operation_done),
        .dcache2arb_dbus_operation_type(dcache2arb_dbus_operation_type),
        .ddr_chip_enable               (ddr_chip_enable),
        .ddr_index                     (ddr_index),
        .ddr_write_enable              (ddr_write_enable),
        .ddr_burst_mode                (ddr_burst_mode),
        .ddr_write_data                (ddr_write_data),
        .ddr_read_data                 (ddr_read_data),
        .ddr_operation_done            (ddr_operation_done),
        .ddr_ready                     (ddr_ready)
    );

    icache u_icache (
        .clock                         (clock),
        .reset_n                       (reset_n),
        .flush                         (flush_valid),
        .tbus_index_valid              (pc_index_valid),
        .tbus_index_ready              (pc_index_ready),
        .tbus_index                    (pc_index),
        .tbus_write_data               ('b0),
        .tbus_write_mask               ('b0),
        .tbus_read_data                (pc_read_inst),
        .tbus_operation_done           (pc_operation_done),
        .tbus_operation_type           (2'b00),
        .icache2arb_dbus_index_valid   (icache2arb_dbus_index_valid),
        .icache2arb_dbus_index_ready   (icache2arb_dbus_index_ready),
        .icache2arb_dbus_index         (icache2arb_dbus_index),
        .icache2arb_dbus_write_data    (icache2arb_dbus_write_data),
        .icache2arb_dbus_read_data     (icache2arb_dbus_read_data),
        .icache2arb_dbus_operation_done(icache2arb_dbus_operation_done),
        .icache2arb_dbus_operation_type()
    );

    dcache u_dcache (
        .clock                         (clock),
        .reset_n                       (reset_n),
        .flush                         (arb2dcache_flush_valid),
        .tbus_index_valid              (tbus_index_valid),
        .tbus_index_ready              (tbus_index_ready),
        .tbus_index                    (tbus_index),
        .tbus_write_data               (tbus_write_data),
        .tbus_write_mask               (tbus_write_mask),
        .tbus_read_data                (tbus_read_data),
        .tbus_operation_done           (tbus_operation_done),
        .tbus_operation_type           (tbus_operation_type),
        .dcache2arb_dbus_index_valid   (dcache2arb_dbus_index_valid),
        .dcache2arb_dbus_index_ready   (dcache2arb_dbus_index_ready),
        .dcache2arb_dbus_index         (dcache2arb_dbus_index),
        .dcache2arb_dbus_write_data    (dcache2arb_dbus_write_data),
        .dcache2arb_dbus_read_data     (dcache2arb_dbus_read_data),
        .dcache2arb_dbus_operation_done(dcache2arb_dbus_operation_done),
        .dcache2arb_dbus_operation_type(dcache2arb_dbus_operation_type)
    );

    /* -------------------------------------------------------------------------- */
    /*                                     frontend                               */
    /* -------------------------------------------------------------------------- */

    frontend u_frontend (
        .clock                         (clock),
        .reset_n                       (reset_n),
        .redirect_valid                (flush_valid),
        .redirect_target               (flush_target),
        .pc_index_valid                (pc_index_valid),
        .pc_index_ready                (pc_index_ready),
        .pc_operation_done             (pc_operation_done),
        .pc_read_inst                  (pc_read_inst),
        .pc_index                      (pc_index),

        // --- [2-wide] 双路输出给 backend ---
        .ibuffer_instr0_ready          (ibuffer_instr0_ready),
        .ibuffer_instr0_valid          (ibuffer_instr0_valid),
        .ibuffer_inst0_out             (ibuffer_inst0_out),
        .ibuffer_pc0_out               (ibuffer_pc0_out),
        .ibuffer_predicttaken0_out     (ibuffer_predicttaken0_out),
        .ibuffer_predicttarget0_out    (ibuffer_predicttarget0_out),

        .ibuffer_instr1_ready          (ibuffer_instr1_ready),
        .ibuffer_instr1_valid          (ibuffer_instr1_valid),
        .ibuffer_inst1_out             (ibuffer_inst1_out),
        .ibuffer_pc1_out               (ibuffer_pc1_out),
        .ibuffer_predicttaken1_out     (ibuffer_predicttaken1_out),
        .ibuffer_predicttarget1_out    (ibuffer_predicttarget1_out),

        .intwb_bht_write_enable        (intwb_bht_write_enable),
        .intwb_bht_write_index         (intwb_bht_write_index),
        .intwb_bht_write_counter_select(intwb_bht_write_counter_select),
        .intwb_bht_write_inc           (intwb_bht_write_inc),
        .intwb_bht_write_dec           (intwb_bht_write_dec),
        .intwb_bht_valid_in            (intwb_bht_valid_in),
        .intwb_btb_ce                  (intwb_btb_ce),
        .intwb_btb_we                  (intwb_btb_we),
        .intwb_btb_wmask               (intwb_btb_wmask),
        .intwb_btb_write_index         (intwb_btb_write_index),
        .intwb_btb_din                 (intwb_btb_din),
        .end_of_program                (end_of_program)
    );

    /* -------------------------------------------------------------------------- */
    /*                                   backend                                  */
    /* -------------------------------------------------------------------------- */

    backend u_backend (
        .clock                    (clock),
        .reset_n                  (reset_n),

        // --- [2-wide] 双路输入来自 frontend ---
        .ibuffer_instr0_valid      (ibuffer_instr0_valid),
        .ibuffer_instr0_ready      (ibuffer_instr0_ready),
        .ibuffer_predicttaken0_out (ibuffer_predicttaken0_out),
        .ibuffer_predicttarget0_out(ibuffer_predicttarget0_out),
        .ibuffer_inst0_out         (ibuffer_inst0_out),
        .ibuffer_pc0_out           (ibuffer_pc0_out),

        .ibuffer_instr1_valid      (ibuffer_instr1_valid),
        .ibuffer_instr1_ready      (ibuffer_instr1_ready),
        .ibuffer_predicttaken1_out (ibuffer_predicttaken1_out),
        .ibuffer_predicttarget1_out(ibuffer_predicttarget1_out),
        .ibuffer_inst1_out         (ibuffer_inst1_out),
        .ibuffer_pc1_out           (ibuffer_pc1_out),

        .flush_valid              (flush_valid),
        .flush_target             (flush_target),
        .tbus_index_valid         (tbus_index_valid),
        .tbus_index_ready         (tbus_index_ready),
        .tbus_index               (tbus_index),
        .tbus_write_data          (tbus_write_data),
        .tbus_write_mask          (tbus_write_mask),
        .tbus_read_data           (tbus_read_data),
        .tbus_operation_done      (tbus_operation_done),
        .tbus_operation_type      (tbus_operation_type),
        .arb2dcache_flush_valid   (arb2dcache_flush_valid),

        .intwb0_bht_write_enable        (intwb_bht_write_enable),
        .intwb0_bht_write_index         (intwb_bht_write_index),
        .intwb0_bht_write_counter_select(intwb_bht_write_counter_select),
        .intwb0_bht_write_inc           (intwb_bht_write_inc),
        .intwb0_bht_write_dec           (intwb_bht_write_dec),
        .intwb0_bht_valid_in            (intwb_bht_valid_in),
        .intwb0_btb_ce                  (intwb_btb_ce),
        .intwb0_btb_we                  (intwb_btb_we),
        .intwb0_btb_wmask               (intwb_btb_wmask),
        .intwb0_btb_write_index         (intwb_btb_write_index),
        .intwb0_btb_din                 (intwb_btb_din),
        .end_of_program                (end_of_program)
    );

endmodule
