module ifu_top (
    input wire clock,
    input wire reset_n,

    // Inputs for PC control
    input  wire [`PC_RANGE] boot_addr,         // 48-bit boot address
    input  wire             interrupt_valid,   // Interrupt valid signal
    input  wire [`PC_RANGE] interrupt_addr,    // 48-bit interrupt address
    input  wire             redirect_valid,    // Branch address valid signal
    input  wire [`PC_RANGE] redirect_target,   // 48-bit branch address
    output wire             pc_index_valid,
    input  wire             pc_index_ready,    // Signal indicating DDR operation is complete
    input  wire             pc_operation_done, // Signal indicating PC operation is done

    // Inputs for instruction buffer
    input wire [`ICACHE_FETCHWIDTH128_RANGE] pc_read_inst,        // 128-bit input data for instructions
    input wire                               ibuffer_instr_ready, // External read enable signal for FIFO
    //input wire        clear_ibuffer_ext, // External clear signal for ibuffer

    // Outputs from ibuffer
    output wire        ibuffer_instr_valid,
    output wire        ibuffer_predicttaken_out,
    output wire [31:0] ibuffer_predicttarget_out,
    output wire [31:0] ibuffer_inst_out,
    output wire [63:0] ibuffer_pc_out,
    output wire        fifo_empty,                 // Signal indicating if the FIFO is empty

    // Outputs from pc_ctrl
    output wire [63:0] pc_index,  // Selected bits [21:3] of the PC for DDR index

    input wire       backend_stall,
    // BHT Write Interface
    input wire       bht_write_enable,          // Write enable for BHT
    input wire [8:0] bht_write_index,           // Set index for BHT write operation
    input wire [1:0] bht_write_counter_select,  // Counter select within the BHT set (0 to 3)
    input wire       bht_write_inc,             // Increment signal for BHT counter
    input wire       bht_write_dec,             // Decrement signal for BHT counter
    input wire       bht_valid_in,              // Valid bit for BHT write operation

    // BTB Write Interface
    input wire         btb_ce,
    input wire         btb_we,           // Write enable for BTB
    input wire [128:0] btb_wmask,
    input wire [  8:0] btb_write_index,  // Set index for BTB write operation
    input wire [128:0] btb_din,
    input  wire end_of_program


);

    // Internal signals connecting ibuffer and pc_ctrl
    wire                               fetch_inst;  // Pulse from ibuffer to trigger fetch in pc_ctrl
    wire                               can_fetch_inst;  // Signal from pc_ctrl to allow fetch in ibuffer

    wire [                       63:0] pc;

    /* --------------------------- bpu related signals -------------------------- */

    // BHT Read Interface
    wire                               pc_req_handshake;
    wire [                        7:0] bht_read_data;  // 8-bit data from BHT (4 counters)
    wire                               bht_valid;  // BHT valid bit
    wire [                       31:0] bht_read_miss_count;  // BHT read miss count

    // Outputs from BTB
    wire [                      127:0] btb_targets;  // Four 32-bit branch target addresses
    wire                               btb_valid;  // BTB valid bit
    wire [                       31:0] btb_read_miss_count;  // BTB read miss count

    /* ----------------------------- admin output signal ---------------------------- */
    wire [`ICACHE_FETCHWIDTH128_RANGE] admin2ib_instr;
    wire [                        3:0] admin2ib_instr_valid;
    wire [                        3:0] admin2ib_predicttaken;
    wire [                   4*32-1:0] admin2ib_predicttarget;
    wire                               admin2pcctrl_predicttaken;
    wire [                       31:0] admin2pcctrl_predicttarget;


    // Instantiate the ibuffer module
    ibuffer ibuffer_inst (
        .clock                    (clock),
        .reset_n                  (reset_n),
        .pc                       (pc),
        .pc_index_ready           (pc_index_ready),
        .pc_operation_done        (pc_operation_done),
        .admin2ib_instr           (admin2ib_instr),
        .admin2ib_instr_valid     (admin2ib_instr_valid),
        .ibuffer_instr_ready      (ibuffer_instr_ready),
        .redirect_valid           (redirect_valid),             // OR external and internal clear signals
        .fetch_inst               (fetch_inst),
        .ibuffer_predicttaken_out (ibuffer_predicttaken_out),
        .ibuffer_predicttarget_out(ibuffer_predicttarget_out),
        .ibuffer_instr_valid      (ibuffer_instr_valid),
        .ibuffer_inst_out         (ibuffer_inst_out),
        .ibuffer_pc_out           (ibuffer_pc_out),
        .fifo_empty               (fifo_empty),
        .backend_stall            (backend_stall),
        .admin2ib_predicttaken    (admin2ib_predicttaken),
        .admin2ib_predicttarget   (admin2ib_predicttarget)

    );


    instr_admin u_instr_admin (
        .pc_operation_done         (pc_operation_done),
        .fetch_instr               (pc_read_inst),
        .pc                        (pc),                         //input
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


    // Instantiate the pc_ctrl module
    pc_ctrl pc_ctrl_inst (
        .clock                     (clock),
        .reset_n                   (reset_n),
        .pc                        (pc),                          //output
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
