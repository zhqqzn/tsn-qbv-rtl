`ifndef SYNTHESIS
module tsn_qbv_list_config_assertions (
  input logic clk_i,
  input logic rst_ni,
  input logic gate_enabled_i,
  input logic config_change_set_i,
  input logic new_config_ct_ack_i,
  input tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  input logic [31:0] admin_base_time_nanoseconds_i,
  input tsn_qbv_pkg::ptp_timestamp_t config_change_time_candidate_i,
  input logic config_pending_o,
  input logic config_accept_o,
  input logic new_config_ct_o,
  input logic [31:0] config_change_time_nanoseconds_i,
  input logic config_pending_state_i,
  input logic config_idle_state_i,
  input tsn_qbv_pkg::ptp_timestamp_t config_change_time_q_i
);

  // Avoid reading the asynchronous reset net in assertion sampling logic.
  // Reset assertion is asynchronous; assertion re-enable is clocked.
  logic assertions_enabled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
    end else begin
      assertions_enabled_q <= 1'b1;
    end
  end

  localparam logic [31:0] NanosecondsPerSecond = 32'd1_000_000_000;

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    current_time_i.nanoseconds < NanosecondsPerSecond
  ) else $fatal(1, "CurrentTime nanoseconds field is not normalized");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    admin_base_time_nanoseconds_i < NanosecondsPerSecond
  ) else $fatal(1, "AdminBaseTime nanoseconds field is not normalized");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    config_pending_o |-> config_change_time_nanoseconds_i < NanosecondsPerSecond
  ) else $fatal(1, "ConfigChangeTime nanoseconds field is not normalized");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    config_accept_o |->
      (config_change_time_candidate_i.nanoseconds < NanosecondsPerSecond)
  ) else $fatal(1, "ConfigChangeTime candidate nanoseconds field is not normalized");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    config_accept_o |->
      ((config_change_time_candidate_i.seconds > current_time_i.seconds) ||
       ((config_change_time_candidate_i.seconds == current_time_i.seconds) &&
        (config_change_time_candidate_i.nanoseconds >= current_time_i.nanoseconds)))
  ) else $fatal(1, "ConfigChangeTime candidate cannot precede CurrentTime");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    (config_pending_state_i && gate_enabled_i) |->
      ((config_change_time_q_i.seconds > current_time_i.seconds) ||
       ((config_change_time_q_i.seconds == current_time_i.seconds) &&
        (config_change_time_q_i.nanoseconds >= current_time_i.nanoseconds)))
  ) else $fatal(1, "ConfigChangeTime was not observed at exact timestamp equality");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    !config_change_set_i || config_idle_state_i
  ) else $fatal(1, "ConfigChange cannot be requested while ConfigPending");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    !new_config_ct_ack_i || new_config_ct_o
  ) else $fatal(1, "Cycle Timer acknowledged NewConfigCT without a request");

endmodule : tsn_qbv_list_config_assertions
`endif
