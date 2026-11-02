module tsn_qbv_apb #(
  parameter int unsigned GclDepth = 64,
  parameter int unsigned TickGranularityNs = 1
) (
  input  logic clk_i,
  input  logic rst_ni,

  // APB4 management port for Admin schedule, GCL programming, and readback.
  input  logic psel_i,
  input  logic penable_i,
  input  logic pwrite_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t paddr_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t pwdata_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t pstrb_i,
  output logic pready_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t prdata_o,
  output logic pslverr_o,

  // PTP timebase is independent of the management bus.
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  input  logic time_tick_i,

  // Functional datapath outputs. Management state is read through APB.
  output tsn_qbv_pkg::gate_state_t oper_gate_states_o,
  output logic cycle_start_o,
  output logic cycle_start_time_valid_o,
  output tsn_qbv_pkg::ptp_timestamp_t cycle_start_time_o
);

  import tsn_qbv_pkg::*;

  localparam int unsigned GclLengthWidth =
      (GclDepth > 1) ? $clog2(GclDepth + 1) : 1;
  localparam logic [GclLengthWidth-1:0] GclLengthEncodingMax = '1;
  localparam bit GclLengthRangeCheckRequired =
      GclLengthEncodingMax > GclLengthWidth'(GclDepth);

  // Core state is consumed internally by the APB register bank. It is not
  // duplicated on the wrapper pins; APB is the management/readback boundary.
  logic core_admin_config_valid;
  logic core_config_change;
  logic core_config_pending;
  ptp_timestamp_t core_config_change_time;
  logic core_config_change_time_valid;
  logic core_config_change_time_overflow;
  logic [63:0] core_config_change_error;
  logic core_list_active;
  logic core_list_complete;
  cycle_time_ns_t core_oper_cycle_time_ns;
  logic [31:0] core_oper_cycle_time_extension_ns;
  logic [GclLengthWidth-1:0] core_admin_control_list_length;
  logic [GclLengthWidth-1:0] core_oper_control_list_length;
  ptp_timestamp_t core_oper_base_time;
  tsn_qbv_admin_config_t core_admin_config;
  tsn_qbv_admin_config_t admin_config_staging;
  logic core_oper_commit;
  logic core_new_config_ct;
  logic core_new_config_ct_ack;
  logic [GclLengthWidth-1:0] core_list_pointer;

  tsn_qbv_admin_config_t admin_config_write_data;
  logic admin_config_write_valid;
  logic admin_config_write_ready;
  logic admin_config_write_error;
  logic admin_config_write_done;
  logic admin_entry_write_valid;
  logic admin_entry_write_done;
  logic admin_entry_write_error;
  logic [((GclDepth > 1) ? $clog2(GclDepth) : 1)-1:0] admin_entry_write_address;
  oper_gcl_entry_t admin_entry_write_data;
  logic admin_store_write_ready;
  logic admin_core_write_error;
  logic admin_length_write_valid;
  logic [GclLengthWidth-1:0] admin_length_write_data;
  logic admin_length_write_done;
  logic admin_length_write_error;
  logic gate_enabled;
  logic config_change_set;

  tsn_qbv_apb_admin_registers #(
    .GclDepth(GclDepth),
    .TickGranularityNs(TickGranularityNs)
  ) u_apb_admin_registers (
    .clk_i,
    .rst_ni,
    .psel_i,
    .penable_i,
    .pwrite_i,
    .paddr_i,
    .pwdata_i,
    .pstrb_i,
    .pready_o,
    .prdata_o,
    .pslverr_o,
    .admin_config_write_valid_o(admin_config_write_valid),
    .admin_config_write_ready_i(admin_config_write_ready),
    .admin_config_write_data_o(admin_config_write_data),
    .admin_config_write_error_i(admin_config_write_error),
    .admin_config_write_done_i(admin_config_write_done),
    .admin_config_valid_i(core_admin_config_valid),
    .config_change_i(core_config_change),
    .config_pending_i(core_config_pending),
    .config_change_time_i(core_config_change_time),
    .config_change_time_valid_i(core_config_change_time_valid),
    .config_change_time_overflow_i(core_config_change_time_overflow),
    .config_change_error_i(core_config_change_error),
    .list_active_i(core_list_active),
    .list_complete_i(core_list_complete),
    .cycle_start_time_valid_i(cycle_start_time_valid_o),
    .gcl_write_error_i(admin_core_write_error),
    .gate_enabled_o(gate_enabled),
    .config_change_set_o(config_change_set),
    .admin_config_staging_o(admin_config_staging),
    .admin_entry_write_valid_o(admin_entry_write_valid),
    .admin_entry_write_ready_i(admin_store_write_ready),
    .admin_entry_write_done_i(admin_entry_write_done),
    .admin_entry_write_error_i(admin_entry_write_error),
    .admin_entry_write_address_o(admin_entry_write_address),
    .admin_entry_write_data_o(admin_entry_write_data),
    .admin_length_write_valid_o(admin_length_write_valid),
    .admin_length_write_ready_i(admin_store_write_ready),
    .admin_length_write_done_i(admin_length_write_done),
    .admin_length_write_error_i(admin_length_write_error),
    .admin_length_write_data_o(admin_length_write_data),
    .admin_control_list_length_i(core_admin_control_list_length),
    .oper_base_time_i(core_oper_base_time),
    .oper_cycle_time_ns_i(core_oper_cycle_time_ns),
    .oper_cycle_time_extension_ns_i(core_oper_cycle_time_extension_ns),
    .oper_control_list_length_i(core_oper_control_list_length),
    .oper_gate_states_i(oper_gate_states_o)
  );

  tsn_qbv #(
    .GclDepth(GclDepth),
    .TickGranularityNs(TickGranularityNs)
  ) u_qbv (
    .clk_i,
    .rst_ni,
    .gate_enabled_i(gate_enabled),
    .config_change_set_i(config_change_set),
    .current_time_i,
    .admin_config_write_valid_i(admin_config_write_valid),
    .admin_config_write_ready_o(admin_config_write_ready),
    .admin_config_write_data_i(admin_config_write_data),
    .admin_config_write_error_o(admin_config_write_error),
    .admin_config_write_done_o(admin_config_write_done),
    .admin_config_valid_o(core_admin_config_valid),
    .admin_config_o(core_admin_config),
    .admin_entry_write_valid_i(admin_entry_write_valid),
    .admin_write_ready_o(admin_store_write_ready),
    .admin_entry_write_address_i(admin_entry_write_address),
    .admin_entry_write_data_i(admin_entry_write_data),
    .admin_length_write_valid_i(admin_length_write_valid),
    .admin_length_write_data_i(admin_length_write_data),
    .admin_write_error_o(admin_core_write_error),
    .admin_entry_write_done_o(admin_entry_write_done),
    .admin_entry_write_error_o(admin_entry_write_error),
    .admin_length_write_done_o(admin_length_write_done),
    .admin_length_write_error_o(admin_length_write_error),
    .time_tick_i,
    .config_change_o(core_config_change),
    .config_pending_o(core_config_pending),
    .config_change_time_o(core_config_change_time),
    .config_change_time_valid_o(core_config_change_time_valid),
    .config_change_time_overflow_o(core_config_change_time_overflow),
    .config_change_error_o(core_config_change_error),
    .oper_commit_o(core_oper_commit),
    .new_config_ct_o(core_new_config_ct),
    .new_config_ct_ack_o(core_new_config_ct_ack),
    .oper_base_time_o(core_oper_base_time),
    .oper_cycle_time_ns_o(core_oper_cycle_time_ns),
    .oper_cycle_time_extension_ns_o(core_oper_cycle_time_extension_ns),
    .admin_control_list_length_o(core_admin_control_list_length),
    .oper_control_list_length_o(core_oper_control_list_length),
    .oper_gate_states_o,
    .list_pointer_o(core_list_pointer),
    .list_active_o(core_list_active),
    .list_complete_o(core_list_complete),
    .cycle_start_o(cycle_start_o),
    .cycle_start_time_valid_o(cycle_start_time_valid_o),
    .cycle_start_time_o(cycle_start_time_o)
  );

`ifndef SYNTHESIS
  if (GclLengthRangeCheckRequired) begin : gen_list_pointer_assertion
    always_comb begin
      if (rst_ni) begin
        assert (core_list_pointer <= GclLengthWidth'(GclDepth))
          else $fatal(1, "Qbv ListPointer exceeded the configured GCL depth");
      end
    end
  end

  always_comb begin
    if (rst_ni) begin
      assert (admin_core_write_error ==
              (admin_entry_write_error || admin_length_write_error))
        else $fatal(1, "GCL store aggregate error did not match operation result");
      assert (!$isunknown(admin_config_staging))
        else $fatal(1, "APB Admin staging image contains unknown bits");
      assert (!$isunknown(core_list_pointer))
        else $fatal(1, "Qbv ListPointer contains unknown bits");
      assert (!core_oper_commit || (core_new_config_ct && core_new_config_ct_ack))
        else $fatal(1, "Qbv Oper commit did not complete the Cycle Timer handoff");
      if (admin_config_write_done && !admin_config_write_error) begin
        assert (core_admin_config == admin_config_write_data)
          else $fatal(1, "Accepted Admin image differs from the APB commit snapshot");
      end
    end
  end
`endif

endmodule : tsn_qbv_apb
