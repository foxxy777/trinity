module idu_top (
    input wire clock,
    input wire reset_n,

    // ports with ibuffer
    input  wire             ibuffer_instr_valid,
    input  wire             ibuffer_predicttaken_out,
    input  wire [     31:0] ibuffer_predicttarget_out,
    input  wire [     31:0] ibuffer_inst_out,
    input  wire [`PC_RANGE] ibuffer_pc_out,
    output wire             ibuffer_instr_ready,

    // flush signals from intwb
    input wire flush_valid,

    // ports with iru
    input  wire                iru2idu_instr_ready,
    output wire                idu2iru_instr_valid,
    output wire [`INSTR_RANGE] idu2iru_instr,
    output wire [   `PC_RANGE] idu2iru_pc,
    output wire [ `LREG_RANGE] idu2iru_lrs1,
    output wire [ `LREG_RANGE] idu2iru_lrs2,
    output wire [ `LREG_RANGE] idu2iru_lrd,
    output wire [  `SRC_RANGE] idu2iru_imm,
    output wire                idu2iru_src1_is_reg,
    output wire                idu2iru_src2_is_reg,
    output wire                idu2iru_need_to_wb,

    output wire [    `CX_TYPE_RANGE] idu2iru_cx_type,
    output wire                      idu2iru_is_unsigned,
    output wire [   `ALU_TYPE_RANGE] idu2iru_alu_type,
    output wire                      idu2iru_is_word,
    output wire                      idu2iru_is_load,
    output wire                      idu2iru_is_imm,
    output wire                      idu2iru_is_store,
    output wire [               3:0] idu2iru_ls_size,
    output wire [`MULDIV_TYPE_RANGE] idu2iru_muldiv_type,

    output wire [`PREG_RANGE] idu2iru_prs1,
    output wire [`PREG_RANGE] idu2iru_prs2,
    output wire [`PREG_RANGE] idu2iru_prd,
    output wire [`PREG_RANGE] idu2iru_old_prd,

    output wire        idu2iru_instr0_predicttaken,
    output wire [31:0] idu2iru_instr0_predicttarget,
    input  wire end_of_program
);

    //----------------------------------
    // Internal signals: decoder -> pipereg_autostall
    //----------------------------------
    wire [               4:0] dec_rs1;
    wire [               4:0] dec_rs2;
    wire [               4:0] dec_rd;
    wire [              63:0] dec_imm;
    wire                      dec_src1_is_reg;
    wire                      dec_src2_is_reg;
    wire                      dec_need_to_wb;
    wire [    `CX_TYPE_RANGE] dec_cx_type;
    wire                      dec_is_unsigned;
    wire [   `ALU_TYPE_RANGE] dec_alu_type;
    wire                      dec_is_word;
    wire                      dec_is_imm;
    wire                      dec_is_load;
    wire                      dec_is_store;
    wire [               3:0] dec_ls_size;
    wire [`MULDIV_TYPE_RANGE] dec_muldiv_type;

    // Decoder output signals (instruction valid, PC, instruction, etc.)
    wire                      dec_instr_valid;
    wire [         `PC_RANGE] dec_pc_out;
    wire [              31:0] dec_instr_out;
    wire                      dec_predicttaken_out;
    wire [              31:0] dec_predicttarget_out;

    //----------------------------------
    // Instantiate decoder module
    //----------------------------------
    decoder u_decoder (
        .clock  (clock),
        .reset_n(reset_n),

        // Inputs from ibuffer
        .ibuffer_instr_valid      (ibuffer_instr_valid),
        .ibuffer_predicttaken_out (ibuffer_predicttaken_out),
        .ibuffer_predicttarget_out(ibuffer_predicttarget_out),
        .ibuffer_inst_out         (ibuffer_inst_out),
        .ibuffer_pc_out           (ibuffer_pc_out),

        // Decoding outputs (registers, control signals, etc.)
        .rs1        (dec_rs1),
        .rs2        (dec_rs2),
        .rd         (dec_rd),
        .imm        (dec_imm),
        .src1_is_reg(dec_src1_is_reg),
        .src2_is_reg(dec_src2_is_reg),
        .need_to_wb (dec_need_to_wb),
        .cx_type    (dec_cx_type),
        .is_unsigned(dec_is_unsigned),
        .alu_type   (dec_alu_type),
        .is_word    (dec_is_word),
        .is_imm     (dec_is_imm),
        .is_load    (dec_is_load),
        .is_store   (dec_is_store),
        .ls_size    (dec_ls_size),
        .muldiv_type(dec_muldiv_type),

        // Feedthrough signals
        .decoder_instr_valid      (dec_instr_valid),
        .decoder_pc_out           (dec_pc_out),
        .decoder_instr_out        (dec_instr_out),
        .decoder_predicttaken_out (dec_predicttaken_out),
        .decoder_predicttarget_out(dec_predicttarget_out)
    );

    //----------------------------------
    // Instantiate pipereg_autostall
    //----------------------------------
    pipereg_autostall u_idu_pipereg_autostall (
        .clock  (clock),
        .reset_n(reset_n),

        /* --------------------------- Inputs from decoder -------------------------- */
        .instr_valid_from_upper(dec_instr_valid),
        .instr_ready_to_upper  (ibuffer_instr_ready), //output

        .instr      (dec_instr_out),
        .pc         (dec_pc_out),
        .lrs1       (dec_rs1),
        .lrs2       (dec_rs2),
        .lrd        (dec_rd),
        .imm        (dec_imm),
        .src1_is_reg(dec_src1_is_reg),
        .src2_is_reg(dec_src2_is_reg),
        .need_to_wb (dec_need_to_wb),

        .cx_type    (dec_cx_type),
        .is_unsigned(dec_is_unsigned),
        .alu_type   (dec_alu_type),
        .is_word    (dec_is_word),
        .is_load    (dec_is_load),
        .is_imm     (dec_is_imm),
        .is_store   (dec_is_store),
        .ls_size    (dec_ls_size),
        .muldiv_type(dec_muldiv_type),

        .prs1   (),
        .prs2   (),
        .prd    (),
        .old_prd(),

        .ls_address         (),
        .alu_result         (),
        .bju_result         (),
        .muldiv_result      (),
        .opload_read_data_wb(),

        .predicttaken (dec_predicttaken_out),
        .predicttarget(dec_predicttarget_out),

        /* ----------------------------- Outputs to IRU ----------------------------- */
        .instr_valid_to_lower  (idu2iru_instr_valid),
        .instr_ready_from_lower(iru2idu_instr_ready),  //input feedthrough

        .lower_instr      (idu2iru_instr),
        .lower_pc         (idu2iru_pc),
        .lower_lrs1       (idu2iru_lrs1),
        .lower_lrs2       (idu2iru_lrs2),
        .lower_lrd        (idu2iru_lrd),
        .lower_imm        (idu2iru_imm),
        .lower_src1_is_reg(idu2iru_src1_is_reg),
        .lower_src2_is_reg(idu2iru_src2_is_reg),
        .lower_need_to_wb (idu2iru_need_to_wb),

        .lower_cx_type    (idu2iru_cx_type),
        .lower_is_unsigned(idu2iru_is_unsigned),
        .lower_alu_type   (idu2iru_alu_type),
        .lower_is_word    (idu2iru_is_word),
        .lower_is_load    (idu2iru_is_load),
        .lower_is_imm     (idu2iru_is_imm),
        .lower_is_store   (idu2iru_is_store),
        .lower_ls_size    (idu2iru_ls_size),
        .lower_muldiv_type(idu2iru_muldiv_type),

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
        // Flush signal
        .flush_valid        (flush_valid)                    //input
    );

endmodule
