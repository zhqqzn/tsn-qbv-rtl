module tsn_qbv #(
  parameter int unsigned GclDepth = 64,
  parameter int unsigned TickGranularityNs = 1
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic gate_enabled_i,
  input  logic config_change_set_i,
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  // Admin schedule parameters are held and validated atomically inside the IP.
  input  logic admin_config_write_valid_i,
  output logic admin_config_write_ready_o,
  input  tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_write_data_i,
  output logic admin_config_write_error_o,
  output logic admin_config_valid_o,
  output tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_o,

  input  logic admin_entry_write_valid_i,
  output logic admin_write_ready_o,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth) : 1)-1:0]
             admin_entry_write_address_i,
  input  tsn_qbv_pkg::oper_gcl_entry_t admin_entry_write_data_i,
  input  logic admin_length_write_valid_i,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
             admin_length_write_data_i,
  output logic admin_write_error_o,

  // One pulse advances CurrentTime by exactly TickGranularityNs.
  input  logic time_tick_i,

  output logic config_change_o,
  output logic config_pending_o,
  // Candidate while idle; immutable accepted target while ConfigPending.
  output tsn_qbv_pkg::ptp_timestamp_t config_change_time_o,
  output logic config_change_time_valid_o,
  output logic config_change_time_overflow_o,
  output logic [63:0] config_change_error_o,
  output logic oper_commit_o,
  output logic new_config_ct_o,
  output logic new_config_ct_ack_o,

  output tsn_qbv_pkg::ptp_timestamp_t oper_base_time_o,
  output tsn_qbv_pkg::cycle_time_ns_t oper_cycle_time_ns_o,
  output logic [31:0] oper_cycle_time_extension_ns_o,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              admin_control_list_length_o,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              oper_control_list_length_o,
  output tsn_qbv_pkg::gate_state_t oper_gate_states_o,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              list_pointer_o,
  output logic list_active_o,
  output logic list_complete_o,
  output logic cycle_start_o,
  output logic cycle_start_time_valid_o,
  output tsn_qbv_pkg::ptp_timestamp_t cycle_start_time_o,
  // One-cycle result pulse for an accepted Admin configuration write.
  output logic admin_config_write_done_o,
  output logic admin_entry_write_done_o,
  output logic admin_entry_write_error_o,
  output logic admin_length_write_done_o,
  output logic admin_length_write_error_o
);

  import tsn_qbv_pkg::*;

  localparam int unsigned ListPointerWidth =
      (GclDepth > 1) ? $clog2(GclDepth + 1) : 1;

  logic config_accept;
  logic cycle_timer_ack;
  logic gcl_admin_write_ready;
  logic gcl_admin_entry_write_done;
  logic gcl_admin_entry_write_error;
  logic gcl_admin_length_write_done;
  logic gcl_admin_length_write_error;
  logic config_accept_ready;
  logic admin_config_valid;
  logic config_change_time_valid;
  logic config_change_time_overflow;
  ptp_timestamp_t config_change_time_candidate;
  ptp_timestamp_t list_config_change_time;
  logic [ListPointerWidth-1:0] oper_list_length;
  oper_gcl_entry_t oper_control_list [GclDepth];

  tsn_qbv_admin_config_t admin_config;
  tsn_qbv_schedule_config_t pending_schedule_config_q;
  tsn_qbv_schedule_config_t oper_schedule_config_q;
  cycle_time_ns_t cycle_timer_oper_cycle_time_ns;
  logic [31:0] cycle_timer_oper_cycle_time_extension_ns;

  // Snapshot schedule timing fields at acceptance; AdminGateStates remains
  // a live Admin attribute used while GateEnabled is false. Both Admin write
  // paths are locked by ConfigPending and unlock after commit or cancellation.
  // The bypass exposes the accepted schedule to Cycle Timer on the same edge
  // that List Config publishes the new GCL into Oper.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_schedule_config_q <= '0;
      oper_schedule_config_q <= '0;
    end else begin
      if (config_accept) begin
        pending_schedule_config_q <= admin_config.schedule;
      end

      if (oper_commit_o) begin
        oper_schedule_config_q <= config_accept
            ? admin_config.schedule
            : pending_schedule_config_q;
      end
    end
  end

  assign cycle_timer_oper_cycle_time_ns =
      oper_commit_o
          ? (config_accept
                 ? admin_config.schedule.cycle_time_ns
                 : pending_schedule_config_q.cycle_time_ns)
          : oper_schedule_config_q.cycle_time_ns;
  assign cycle_timer_oper_cycle_time_extension_ns = oper_commit_o
      ? (config_accept ? admin_config.schedule.cycle_time_extension_ns :
                         pending_schedule_config_q.cycle_time_extension_ns)
      : oper_schedule_config_q.cycle_time_extension_ns;

  assign admin_write_ready_o = gcl_admin_write_ready;
  assign admin_entry_write_done_o = gcl_admin_entry_write_done;
  assign admin_entry_write_error_o = gcl_admin_entry_write_error;
  assign admin_length_write_done_o = gcl_admin_length_write_done;
  assign admin_length_write_error_o = gcl_admin_length_write_error;
  assign admin_config_valid_o = admin_config_valid;
  assign admin_config_o = admin_config;
  // Before acceptance, expose the calculated candidate. During ConfigPending,
  // expose the immutable target already captured by List Config.
  assign config_change_time_o = config_pending_o ? list_config_change_time :
                                                        config_change_time_candidate;
  assign config_change_time_valid_o = admin_config_valid &&
                                      (config_pending_o || config_change_time_valid);
  assign config_change_time_overflow_o = admin_config_valid &&
                                         !config_pending_o && config_change_time_overflow;
  // Do not accept ConfigChange until an Admin image and its change time are valid.
  assign config_accept_ready = admin_config_valid && config_change_time_valid;
  assign oper_base_time_o = oper_schedule_config_q.base_time;
  assign oper_cycle_time_ns_o = oper_schedule_config_q.cycle_time_ns;
  assign oper_cycle_time_extension_ns_o = oper_schedule_config_q.cycle_time_extension_ns;
  assign oper_control_list_length_o = oper_list_length;

  // Calculate the first AdminCycleTime boundary not earlier than CurrentTime.
  tsn_qbv_config_change_time #(
    .TickGranularityNs(TickGranularityNs)
  ) u_config_change_time (
    .admin_base_time_i(admin_config.schedule.base_time),
    .admin_cycle_time_ns_i(admin_config.schedule.cycle_time_ns),
    .current_time_i,
    .config_change_time_o(config_change_time_candidate),
    .config_change_time_valid_o(config_change_time_valid),
    .config_change_time_overflow_o(config_change_time_overflow)
  );

  tsn_qbv_admin_config #(
    .TickGranularityNs(TickGranularityNs)
  ) u_admin_config (
    .clk_i,
    .rst_ni,
    .config_pending_i(config_pending_o),
    .current_time_i,
    .admin_config_write_valid_i,
    .admin_config_write_ready_o,
    .admin_config_write_data_i,
    .admin_config_write_error_o,
    .admin_config_write_done_o,
    .admin_config_valid_o(admin_config_valid),
    .admin_config_o(admin_config)
  );

  tsn_qbv_list_config u_list_config (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .config_accept_ready_i(config_accept_ready),
    .config_change_set_i,
    .new_config_ct_ack_i(cycle_timer_ack),
    .current_time_i,
    .admin_base_time_i(admin_config.schedule.base_time),
    .config_change_time_candidate_i(config_change_time_candidate),
    .config_change_o,
    .config_pending_o,
    .config_accept_o(config_accept),
    .new_config_ct_o,
    .oper_commit_o,
    .config_change_time_o(list_config_change_time),
    .config_change_error_o
  );

  tsn_qbv_gcl_store #(
    .GclDepth(GclDepth)
  ) u_gcl_store (
    .clk_i,
    .rst_ni,
    .config_pending_i(config_pending_o),
    .oper_commit_i(oper_commit_o),
    .admin_entry_write_valid_i,
    .admin_write_ready_o(gcl_admin_write_ready),
    .admin_entry_write_address_i,
    .admin_entry_write_data_i,
    .admin_length_write_valid_i,
    .admin_length_write_data_i,
    .admin_write_error_o,
    .admin_entry_write_done_o(gcl_admin_entry_write_done),
    .admin_entry_write_error_o(gcl_admin_entry_write_error),
    .admin_length_write_done_o(gcl_admin_length_write_done),
    .admin_length_write_error_o(gcl_admin_length_write_error),
    .admin_control_list_length_o,
    .oper_control_list_length_o(oper_list_length),
    .oper_control_list_o(oper_control_list)
  );

  tsn_qbv_cycle_timer #(
    .TickGranularityNs(TickGranularityNs)
  ) u_cycle_timer (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .config_pending_i(config_pending_o),
    .config_change_time_i(config_change_time_o),
    .new_config_ct_i(new_config_ct_o),
    .oper_cycle_time_ns_i(cycle_timer_oper_cycle_time_ns),
    .oper_cycle_time_extension_ns_i(cycle_timer_oper_cycle_time_extension_ns),
    .current_time_i,
    .cycle_start_o,
    .cycle_start_time_valid_o,
    .cycle_start_time_o,
    .new_config_ct_ack_o(cycle_timer_ack)
  );

  assign new_config_ct_ack_o = cycle_timer_ack;

  tsn_qbv_list_execute #(
    .GclDepth(GclDepth)
  ) u_list_execute (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .cycle_start_i(cycle_start_o),
    .time_tick_i,
    .admin_gate_states_i(admin_config.admin_gate_states),
    .oper_control_list_length_i(oper_list_length),
    .oper_control_list_i(oper_control_list),
    .oper_gate_states_o,
    .list_pointer_o,
    .list_active_o,
    .list_complete_o
  );


endmodule : tsn_qbv
