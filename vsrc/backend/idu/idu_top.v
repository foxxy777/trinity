// ============================================================
// idu_top.v — IDU 顶层（双 decoder + 双 pipereg）（2-wide 改造版）
// ============================================================
// [2-wide] 改动说明：
//   原来：单路 ibuffer 输入 → 1 个 decoder → 1 个 pipereg → 单路输出给 IRU
//   现在：双路 ibuffer 输入 → 2 个 decoder → 2 个 pipereg → 双路输出给 IRU
//
// 改动内容：
//   1. 输入端口：单路 → 双路（instr0_* + instr1_*）
//   2. 例化 2 个 decoder（decoder.v 零改动）
//   3. 例化 2 个 pipereg_autostall（pipereg_autostall.v 零改动）
//   4. 输出端口：单路 → 双路（idu2iru_instr0_* + idu2iru_instr1_*）
//
// 不改的部分：
//   - decoder.v（零改动）
//   - pipereg_autostall.v（零改动）
// ============================================================

module idu_top (
    input wire clock,
    input wire reset_n,

    // --- [2-wide] 双路 ibuffer 输入（原先是单路） ---
    // instr0: 第 1 条指令
    input  wire             ibuffer_instr0_valid,
    input  wire             ibuffer_predicttaken0_out,
    input  wire [     31:0] ibuffer_predicttarget0_out,
    input  wire [     31:0] ibuffer_inst0_out,
    input  wire [`PC_RANGE] ibuffer_pc0_out,
    output wire             ibuffer_instr0_ready,

    // instr1: 第 2 条指令
    input  wire             ibuffer_instr1_valid,
    input  wire             ibuffer_predicttaken1_out,
    input  wire [     31:0] ibuffer_predicttarget1_out,
    input  wire [     31:0] ibuffer_inst1_out,
    input  wire [`PC_RANGE] ibuffer_pc1_out,
    output wire             ibuffer_instr1_ready,

    // flush signals from intwb
    input wire flush_valid,

    // --- [2-wide] 双路输出给 IRU ---
    // instr0 输出（原来没有 instr0 后缀，现在加上）
    input  wire                iru2idu_instr0_ready,
    output wire                idu2iru_instr0_valid,
    output wire [`INSTR_RANGE] idu2iru_instr0_instr,
    output wire [   `PC_RANGE] idu2iru_instr0_pc,
    output wire [ `LREG_RANGE] idu2iru_instr0_lrs1,
    output wire [ `LREG_RANGE] idu2iru_instr0_lrs2,
    output wire [ `LREG_RANGE] idu2iru_instr0_lrd,
    output wire [  `SRC_RANGE] idu2iru_instr0_imm,
    output wire                idu2iru_instr0_src1_is_reg,
    output wire                idu2iru_instr0_src2_is_reg,
    output wire                idu2iru_instr0_need_to_wb,
    output wire [    `CX_TYPE_RANGE] idu2iru_instr0_cx_type,
    output wire                      idu2iru_instr0_is_unsigned,
    output wire [   `ALU_TYPE_RANGE] idu2iru_instr0_alu_type,
    output wire                      idu2iru_instr0_is_word,
    output wire                      idu2iru_instr0_is_load,
    output wire                      idu2iru_instr0_is_imm,
    output wire                      idu2iru_instr0_is_store,
    output wire [               3:0] idu2iru_instr0_ls_size,
    output wire [`MULDIV_TYPE_RANGE] idu2iru_instr0_muldiv_type,
    output wire [`PREG_RANGE] idu2iru_instr0_prs1,
    output wire [`PREG_RANGE] idu2iru_instr0_prs2,
    output wire [`PREG_RANGE] idu2iru_instr0_prd,
    output wire [`PREG_RANGE] idu2iru_instr0_old_prd,
    output wire        idu2iru_instr0_predicttaken,
    output wire [31:0] idu2iru_instr0_predicttarget,

    // [2-wide] instr1 输出（新增）
    input  wire                iru2idu_instr1_ready,
    output wire                idu2iru_instr1_valid,
    output wire [`INSTR_RANGE] idu2iru_instr1_instr,
    output wire [   `PC_RANGE] idu2iru_instr1_pc,
    output wire [ `LREG_RANGE] idu2iru_instr1_lrs1,
    output wire [ `LREG_RANGE] idu2iru_instr1_lrs2,
    output wire [ `LREG_RANGE] idu2iru_instr1_lrd,
    output wire [  `SRC_RANGE] idu2iru_instr1_imm,
    output wire                idu2iru_instr1_src1_is_reg,
    output wire                idu2iru_instr1_src2_is_reg,
    output wire                idu2iru_instr1_need_to_wb,
    output wire [    `CX_TYPE_RANGE] idu2iru_instr1_cx_type,
    output wire                      idu2iru_instr1_is_unsigned,
    output wire [   `ALU_TYPE_RANGE] idu2iru_instr1_alu_type,
    output wire                      idu2iru_instr1_is_word,
    output wire                      idu2iru_instr1_is_load,
    output wire                      idu2iru_instr1_is_imm,
    output wire                      idu2iru_instr1_is_store,
    output wire [               3:0] idu2iru_instr1_ls_size,
    output wire [`MULDIV_TYPE_RANGE] idu2iru_instr1_muldiv_type,
    output wire [`PREG_RANGE] idu2iru_instr1_prs1,
    output wire [`PREG_RANGE] idu2iru_instr1_prs2,
    output wire [`PREG_RANGE] idu2iru_instr1_prd,
    output wire [`PREG_RANGE] idu2iru_instr1_old_prd,
    output wire        idu2iru_instr1_predicttaken,
    output wire [31:0] idu2iru_instr1_predicttarget,

    input  wire end_of_program
);

    // ============================================================
    // Decoder 0 — 处理 instr0（原始路径，decoder.v 零改动）
    // ============================================================
    wire [               4:0] dec0_rs1;
    wire [               4:0] dec0_rs2;
    wire [               4:0] dec0_rd;
    wire [              63:0] dec0_imm;
    wire                      dec0_src1_is_reg;
    wire                      dec0_src2_is_reg;
    wire                      dec0_need_to_wb;
    wire [    `CX_TYPE_RANGE] dec0_cx_type;
    wire                      dec0_is_unsigned;
    wire [   `ALU_TYPE_RANGE] dec0_alu_type;
    wire                      dec0_is_word;
    wire                      dec0_is_imm;
    wire                      dec0_is_load;
    wire                      dec0_is_store;
    wire [               3:0] dec0_ls_size;
    wire [`MULDIV_TYPE_RANGE] dec0_muldiv_type;
    wire                      dec0_instr_valid;
    wire [         `PC_RANGE] dec0_pc_out;
    wire [              31:0] dec0_instr_out;
    wire                      dec0_predicttaken_out;
    wire [              31:0] dec0_predicttarget_out;

    // --- [2-wide] decoder0 例化（接收 instr0） ---
    decoder u_decoder0 (
        .clock  (clock),
        .reset_n(reset_n),
        .ibuffer_instr_valid      (ibuffer_instr0_valid),
        .ibuffer_predicttaken_out (ibuffer_predicttaken0_out),
        .ibuffer_predicttarget_out(ibuffer_predicttarget0_out),
        .ibuffer_inst_out         (ibuffer_inst0_out),
        .ibuffer_pc_out           (ibuffer_pc0_out),
        .rs1        (dec0_rs1),
        .rs2        (dec0_rs2),
        .rd         (dec0_rd),
        .imm        (dec0_imm),
        .src1_is_reg(dec0_src1_is_reg),
        .src2_is_reg(dec0_src2_is_reg),
        .need_to_wb (dec0_need_to_wb),
        .cx_type    (dec0_cx_type),
        .is_unsigned(dec0_is_unsigned),
        .alu_type   (dec0_alu_type),
        .is_word    (dec0_is_word),
        .is_imm     (dec0_is_imm),
        .is_load    (dec0_is_load),
        .is_store   (dec0_is_store),
        .ls_size    (dec0_ls_size),
        .muldiv_type(dec0_muldiv_type),
        .decoder_instr_valid      (dec0_instr_valid),
        .decoder_pc_out           (dec0_pc_out),
        .decoder_instr_out        (dec0_instr_out),
        .decoder_predicttaken_out (dec0_predicttaken_out),
        .decoder_predicttarget_out(dec0_predicttarget_out)
    );

    // --- [2-wide] pipereg0 例化（decoder0 → IRU instr0） ---
    pipereg_autostall u_idu_pipereg0 (
        .clock  (clock),
        .reset_n(reset_n),
        .instr_valid_from_upper(dec0_instr_valid),
        .instr_ready_to_upper  (ibuffer_instr0_ready),
        .instr      (dec0_instr_out),
        .pc         (dec0_pc_out),
        .lrs1       (dec0_rs1),
        .lrs2       (dec0_rs2),
        .lrd        (dec0_rd),
        .imm        (dec0_imm),
        .src1_is_reg(dec0_src1_is_reg),
        .src2_is_reg(dec0_src2_is_reg),
        .need_to_wb (dec0_need_to_wb),
        .cx_type    (dec0_cx_type),
        .is_unsigned(dec0_is_unsigned),
        .alu_type   (dec0_alu_type),
        .is_word    (dec0_is_word),
        .is_load    (dec0_is_load),
        .is_imm     (dec0_is_imm),
        .is_store   (dec0_is_store),
        .ls_size    (dec0_ls_size),
        .muldiv_type(dec0_muldiv_type),
        .prs1   (),
        .prs2   (),
        .prd    (),
        .old_prd(),
        .ls_address         (),
        .alu_result         (),
        .bju_result         (),
        .muldiv_result      (),
        .opload_read_data_wb(),
        .predicttaken (dec0_predicttaken_out),
        .predicttarget(dec0_predicttarget_out),
        .instr_valid_to_lower  (idu2iru_instr0_valid),
        .instr_ready_from_lower(iru2idu_instr0_ready),
        .lower_instr      (idu2iru_instr0_instr),
        .lower_pc         (idu2iru_instr0_pc),
        .lower_lrs1       (idu2iru_instr0_lrs1),
        .lower_lrs2       (idu2iru_instr0_lrs2),
        .lower_lrd        (idu2iru_instr0_lrd),
        .lower_imm        (idu2iru_instr0_imm),
        .lower_src1_is_reg(idu2iru_instr0_src1_is_reg),
        .lower_src2_is_reg(idu2iru_instr0_src2_is_reg),
        .lower_need_to_wb (idu2iru_instr0_need_to_wb),
        .lower_cx_type    (idu2iru_instr0_cx_type),
        .lower_is_unsigned(idu2iru_instr0_is_unsigned),
        .lower_alu_type   (idu2iru_instr0_alu_type),
        .lower_is_word    (idu2iru_instr0_is_word),
        .lower_is_load    (idu2iru_instr0_is_load),
        .lower_is_imm     (idu2iru_instr0_is_imm),
        .lower_is_store   (idu2iru_instr0_is_store),
        .lower_ls_size    (idu2iru_instr0_ls_size),
        .lower_muldiv_type(idu2iru_instr0_muldiv_type),
        .lower_prs1   (),
        .lower_prs2   (),
        .lower_prd    (),
        .lower_old_prd(),
        .lower_ls_address         (),
        .lower_alu_result         (),
        .lower_bju_result         (),
        .lower_muldiv_result      (),
        .lower_opload_read_data_wb(),
        .lower_predicttaken (idu2iru_instr0_predicttaken),
        .lower_predicttarget(idu2iru_instr0_predicttarget),
        .flush_valid        (flush_valid)
    );

    // ============================================================
    // [2-wide] Decoder 1 — 处理 instr1（新增路径）
    // 和 decoder0 完全相同，只是输入来自 ibuffer 的第 2 路输出
    // ============================================================
    wire [               4:0] dec1_rs1;
    wire [               4:0] dec1_rs2;
    wire [               4:0] dec1_rd;
    wire [              63:0] dec1_imm;
    wire                      dec1_src1_is_reg;
    wire                      dec1_src2_is_reg;
    wire                      dec1_need_to_wb;
    wire [    `CX_TYPE_RANGE] dec1_cx_type;
    wire                      dec1_is_unsigned;
    wire [   `ALU_TYPE_RANGE] dec1_alu_type;
    wire                      dec1_is_word;
    wire                      dec1_is_imm;
    wire                      dec1_is_load;
    wire                      dec1_is_store;
    wire [               3:0] dec1_ls_size;
    wire [`MULDIV_TYPE_RANGE] dec1_muldiv_type;
    wire                      dec1_instr_valid;
    wire [         `PC_RANGE] dec1_pc_out;
    wire [              31:0] dec1_instr_out;
    wire                      dec1_predicttaken_out;
    wire [              31:0] dec1_predicttarget_out;

    decoder u_decoder1 (
        .clock  (clock),
        .reset_n(reset_n),
        .ibuffer_instr_valid      (ibuffer_instr1_valid),
        .ibuffer_predicttaken_out (ibuffer_predicttaken1_out),
        .ibuffer_predicttarget_out(ibuffer_predicttarget1_out),
        .ibuffer_inst_out         (ibuffer_inst1_out),
        .ibuffer_pc_out           (ibuffer_pc1_out),
        .rs1        (dec1_rs1),
        .rs2        (dec1_rs2),
        .rd         (dec1_rd),
        .imm        (dec1_imm),
        .src1_is_reg(dec1_src1_is_reg),
        .src2_is_reg(dec1_src2_is_reg),
        .need_to_wb (dec1_need_to_wb),
        .cx_type    (dec1_cx_type),
        .is_unsigned(dec1_is_unsigned),
        .alu_type   (dec1_alu_type),
        .is_word    (dec1_is_word),
        .is_imm     (dec1_is_imm),
        .is_load    (dec1_is_load),
        .is_store   (dec1_is_store),
        .ls_size    (dec1_ls_size),
        .muldiv_type(dec1_muldiv_type),
        .decoder_instr_valid      (dec1_instr_valid),
        .decoder_pc_out           (dec1_pc_out),
        .decoder_instr_out        (dec1_instr_out),
        .decoder_predicttaken_out (dec1_predicttaken_out),
        .decoder_predicttarget_out(dec1_predicttarget_out)
    );

    pipereg_autostall u_idu_pipereg1 (
        .clock  (clock),
        .reset_n(reset_n),
        .instr_valid_from_upper(dec1_instr_valid),
        .instr_ready_to_upper  (ibuffer_instr1_ready),
        .instr      (dec1_instr_out),
        .pc         (dec1_pc_out),
        .lrs1       (dec1_rs1),
        .lrs2       (dec1_rs2),
        .lrd        (dec1_rd),
        .imm        (dec1_imm),
        .src1_is_reg(dec1_src1_is_reg),
        .src2_is_reg(dec1_src2_is_reg),
        .need_to_wb (dec1_need_to_wb),
        .cx_type    (dec1_cx_type),
        .is_unsigned(dec1_is_unsigned),
        .alu_type   (dec1_alu_type),
        .is_word    (dec1_is_word),
        .is_load    (dec1_is_load),
        .is_imm     (dec1_is_imm),
        .is_store   (dec1_is_store),
        .ls_size    (dec1_ls_size),
        .muldiv_type(dec1_muldiv_type),
        .prs1   (),
        .prs2   (),
        .prd    (),
        .old_prd(),
        .ls_address         (),
        .alu_result         (),
        .bju_result         (),
        .muldiv_result      (),
        .opload_read_data_wb(),
        .predicttaken (dec1_predicttaken_out),
        .predicttarget(dec1_predicttarget_out),
        .instr_valid_to_lower  (idu2iru_instr1_valid),
        .instr_ready_from_lower(iru2idu_instr1_ready),
        .lower_instr      (idu2iru_instr1_instr),
        .lower_pc         (idu2iru_instr1_pc),
        .lower_lrs1       (idu2iru_instr1_lrs1),
        .lower_lrs2       (idu2iru_instr1_lrs2),
        .lower_lrd        (idu2iru_instr1_lrd),
        .lower_imm        (idu2iru_instr1_imm),
        .lower_src1_is_reg(idu2iru_instr1_src1_is_reg),
        .lower_src2_is_reg(idu2iru_instr1_src2_is_reg),
        .lower_need_to_wb (idu2iru_instr1_need_to_wb),
        .lower_cx_type    (idu2iru_instr1_cx_type),
        .lower_is_unsigned(idu2iru_instr1_is_unsigned),
        .lower_alu_type   (idu2iru_instr1_alu_type),
        .lower_is_word    (idu2iru_instr1_is_word),
        .lower_is_load    (idu2iru_instr1_is_load),
        .lower_is_imm     (idu2iru_instr1_is_imm),
        .lower_is_store   (idu2iru_instr1_is_store),
        .lower_ls_size    (idu2iru_instr1_ls_size),
        .lower_muldiv_type(idu2iru_instr1_muldiv_type),
        .lower_prs1   (),
        .lower_prs2   (),
        .lower_prd    (),
        .lower_old_prd(),
        .lower_ls_address         (),
        .lower_alu_result         (),
        .lower_bju_result         (),
        .lower_muldiv_result      (),
        .lower_opload_read_data_wb(),
        .lower_predicttaken (idu2iru_instr1_predicttaken),
        .lower_predicttarget(idu2iru_instr1_predicttarget),
        .flush_valid        (flush_valid)
    );

endmodule
