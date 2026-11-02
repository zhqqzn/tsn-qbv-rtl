`ifndef SYNTHESIS
module tsn_qbv_assertions #(
  parameter int unsigned TickGranularityNs = 1
) (
  input logic clk_i,
  input logic rst_ni,
  input logic config_accept_i,
  input logic time_tick_i,
  input tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  input tsn_qbv_pkg::ptp_timestamp_t admin_base_time_i,
  input tsn_qbv_pkg::cycle_time_ns_t admin_cycle_time_ns_i,
  input tsn_qbv_pkg::ptp_timestamp_t config_change_time_candidate_i
);

  // Avoid reading the asynchronous reset net in assertion sampling logic.
  logic assertions_enabled_q;
  tsn_qbv_pkg::ptp_time_ns_t current_time_ns;
  tsn_qbv_pkg::ptp_time_ns_t last_observed_time_ns_q;

  localparam tsn_qbv_pkg::ptp_time_ns_t NanosecondsPerSecond = 80'd1_000_000_000;

  function automatic tsn_qbv_pkg::ptp_time_ns_t timestamp_to_nanoseconds(
    input tsn_qbv_pkg::ptp_timestamp_t timestamp
  );
    tsn_qbv_pkg::ptp_time_ns_t seconds_ns;
    seconds_ns = tsn_qbv_pkg::ptp_time_ns_t'(timestamp.seconds) * NanosecondsPerSecond;
    return seconds_ns + tsn_qbv_pkg::ptp_time_ns_t'(timestamp.nanoseconds);
  endfunction

  assign current_time_ns = timestamp_to_nanoseconds(current_time_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
      last_observed_time_ns_q <= '0;
    end else begin
      assertions_enabled_q <= 1'b1;
      last_observed_time_ns_q <= current_time_ns;
    end
  end

  // The executor consumes one interval tick for every implementation-timebase
  // step. Keep that enable and the PTP time input on the same timebase: time
  // advances by exactly TickGranularityNs when time_tick_i is asserted and
  // remains unchanged on every other clock.
  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    time_tick_i |-> current_time_ns ==
                   (last_observed_time_ns_q + tsn_qbv_pkg::ptp_time_ns_t'(TickGranularityNs))
  ) else $fatal(1, "time_tick_i must advance CurrentTime by TickGranularityNs");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    !time_tick_i |-> current_time_ns == last_observed_time_ns_q
  ) else $fatal(1, "CurrentTime changed without time_tick_i");

  function automatic logic config_change_time_is_valid(
    input tsn_qbv_pkg::ptp_timestamp_t admin_base_time,
    input tsn_qbv_pkg::ptp_timestamp_t current_time,
    input tsn_qbv_pkg::ptp_timestamp_t config_change_time,
    input tsn_qbv_pkg::cycle_time_ns_t cycle_time_ns
  );
    tsn_qbv_pkg::ptp_time_ns_t admin_base_time_ns;
    tsn_qbv_pkg::ptp_time_ns_t current_time_absolute_ns;
    tsn_qbv_pkg::ptp_time_ns_t config_change_time_ns;
    tsn_qbv_pkg::ptp_time_ns_t cycle_period_ns;
    tsn_qbv_pkg::ptp_time_ns_t cycle_delta_ns;

    admin_base_time_ns =
        (tsn_qbv_pkg::ptp_time_ns_t'(admin_base_time.seconds) * NanosecondsPerSecond) +
        tsn_qbv_pkg::ptp_time_ns_t'(admin_base_time.nanoseconds);
    current_time_absolute_ns =
        (tsn_qbv_pkg::ptp_time_ns_t'(current_time.seconds) * NanosecondsPerSecond) +
        tsn_qbv_pkg::ptp_time_ns_t'(current_time.nanoseconds);
    config_change_time_ns =
        (tsn_qbv_pkg::ptp_time_ns_t'(config_change_time.seconds) * NanosecondsPerSecond) +
        tsn_qbv_pkg::ptp_time_ns_t'(config_change_time.nanoseconds);
    cycle_period_ns = tsn_qbv_pkg::ptp_time_ns_t'(cycle_time_ns);

    if (cycle_period_ns == '0) begin
      return 1'b0;
    end

    if (admin_base_time_ns >= current_time_absolute_ns) begin
      return config_change_time_ns == admin_base_time_ns;
    end

    if (config_change_time_ns < current_time_absolute_ns) begin
      return 1'b0;
    end

    cycle_delta_ns = config_change_time_ns - admin_base_time_ns;
    if ((cycle_delta_ns % cycle_period_ns) != '0) begin
      return 1'b0;
    end

    // The candidate must be the first AdminCycleTime boundary not earlier
    // than CurrentTime, rather than any later point on the same phase.
    return (config_change_time_ns - current_time_absolute_ns) < cycle_period_ns;
  endfunction

  function automatic logic admin_cycle_time_is_valid(
    input tsn_qbv_pkg::cycle_time_ns_t cycle_time_ns
  );
    if ((TickGranularityNs == 0) || (cycle_time_ns == '0)) begin
      return 1'b0;
    end
    return (cycle_time_ns % 64'(TickGranularityNs)) == '0;
  endfunction

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    config_accept_i |-> admin_cycle_time_is_valid(admin_cycle_time_ns_i)
  ) else $fatal(1, "AdminCycleTime must be positive and TickGranularity-aligned");

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    config_accept_i |-> config_change_time_is_valid(
      admin_base_time_i,
      current_time_i,
      config_change_time_candidate_i,
      admin_cycle_time_ns_i
    )
  ) else $fatal(1, "ConfigChangeTime candidate violates SetConfigChangeTime");

endmodule : tsn_qbv_assertions
`endif
