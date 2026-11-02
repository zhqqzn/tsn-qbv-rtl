// SPDX-License-Identifier: Apache-2.0
// Bind Qbv protocol assertions without adding verification dependencies
// to the RTL modules.
module tsn_qbv_sva_bind;

  bind tsn_qbv tsn_qbv_assertions #(
    .TickGranularityNs(TickGranularityNs)
  ) u_assertions (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .config_accept_i(config_accept),
    .time_tick_i(time_tick_i),
    .current_time_i(current_time_i),
    .admin_base_time_i(admin_config.schedule.base_time),
    .admin_cycle_time_ns_i(admin_config.schedule.cycle_time_ns),
    .config_change_time_candidate_i(config_change_time_candidate)
  );

  bind tsn_qbv_gcl_store tsn_qbv_gcl_store_assertions u_assertions (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .config_pending_i(config_pending_i),
    .oper_commit_i(oper_commit_i)
  );

  bind tsn_qbv_list_config tsn_qbv_list_config_assertions u_assertions (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .gate_enabled_i(gate_enabled_i),
    .config_change_set_i(config_change_set_i),
    .new_config_ct_ack_i(new_config_ct_ack_i),
    .current_time_i(current_time_i),
    .admin_base_time_nanoseconds_i(admin_base_time_i.nanoseconds),
    .config_change_time_candidate_i(config_change_time_candidate_i),
    .config_pending_o(config_pending_o),
    .config_accept_o(config_accept_o),
    .new_config_ct_o(new_config_ct_o),
    .config_change_time_nanoseconds_i(config_change_time_o.nanoseconds),
    .config_pending_state_i(state_q == StConfigPending),
    .config_idle_state_i(state_q == StConfigIdle),
    .config_change_time_q_i(config_change_time_q)
  );

endmodule : tsn_qbv_sva_bind
