module tsn_qbv_admin_config #(
  parameter int unsigned TickGranularityNs = 1
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic config_pending_i,
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  input  logic admin_config_write_valid_i,
  output logic admin_config_write_ready_o,
  input  tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_write_data_i,
  output logic admin_config_write_error_o,
  output logic admin_config_valid_o,
  output tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_o,
  // One-cycle completion pulse; write_error_o qualifies the same result.
  output logic admin_config_write_done_o
);

  import tsn_qbv_pkg::*;

  localparam ptp_time_ns_t NanosecondsPerSecond = 80'd1_000_000_000;

  tsn_qbv_admin_config_t admin_config_q;
  logic admin_config_write_error_q;
  logic admin_config_write_done_q;
  logic admin_config_valid_q;

  function automatic ptp_time_ns_t timestamp_to_nanoseconds(
    input ptp_timestamp_t timestamp
  );
    ptp_time_ns_t seconds_ns;
    seconds_ns = ptp_time_ns_t'(timestamp.seconds) * NanosecondsPerSecond;
    return seconds_ns + ptp_time_ns_t'(timestamp.nanoseconds);
  endfunction

  // Validate the complete image before replacing the stored Admin parameters.
  // The base-time phase is checked against CurrentTime; subsequent time advances
  // preserve this alignment because CurrentTime advances only by whole ticks.
  function automatic logic admin_config_is_valid(
    input tsn_qbv_schedule_config_t candidate_schedule,
    input ptp_timestamp_t current_time
  );
    ptp_time_ns_t base_time_ns;
    ptp_time_ns_t current_time_ns;
    ptp_time_ns_t base_time_delta_ns;

    if (TickGranularityNs == 0 ||
        candidate_schedule.base_time.nanoseconds >= 32'd1_000_000_000 ||
        current_time.nanoseconds >= 32'd1_000_000_000 ||
        candidate_schedule.cycle_time_ns == '0) begin
      return 1'b0;
    end

    if ((candidate_schedule.cycle_time_ns % 64'(TickGranularityNs)) != '0 ||
        (candidate_schedule.cycle_time_extension_ns % 32'(TickGranularityNs)) != '0) begin
      return 1'b0;
    end

    base_time_ns = timestamp_to_nanoseconds(candidate_schedule.base_time);
    current_time_ns = timestamp_to_nanoseconds(current_time);
    if (base_time_ns >= current_time_ns) begin
      base_time_delta_ns = base_time_ns - current_time_ns;
    end else begin
      base_time_delta_ns = current_time_ns - base_time_ns;
    end

    return (base_time_delta_ns % 80'(TickGranularityNs)) == '0;
  endfunction

  // ConfigChange may remain latched while disabled, in which case Admin stays
  // writable. Only ConfigPending locks this bank.
  assign admin_config_write_ready_o = rst_ni && !config_pending_i;
  assign admin_config_write_error_o = admin_config_write_error_q;
  assign admin_config_write_done_o = admin_config_write_done_q;
  assign admin_config_valid_o = admin_config_valid_q;
  assign admin_config_o = admin_config_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      admin_config_q <= '{
        schedule: '{
          base_time: '0,
          cycle_time_ns: '0,
          cycle_time_extension_ns: '0
        },
        admin_gate_states: '1
      };
      admin_config_write_error_q <= 1'b0;
      admin_config_write_done_q <= 1'b0;
      admin_config_valid_q <= 1'b0;
    end else begin
      admin_config_write_error_q <= 1'b0;
      admin_config_write_done_q <= 1'b0;

      if (admin_config_write_valid_i && admin_config_write_ready_o) begin
        admin_config_write_done_q <= 1'b1;
        if (admin_config_is_valid(admin_config_write_data_i.schedule, current_time_i)) begin
          admin_config_q <= admin_config_write_data_i;
          admin_config_valid_q <= 1'b1;
        end else begin
          admin_config_write_error_q <= 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (TickGranularityNs > 0)
      else $fatal(1, "TickGranularityNs must be positive");
  end
`endif

endmodule : tsn_qbv_admin_config
