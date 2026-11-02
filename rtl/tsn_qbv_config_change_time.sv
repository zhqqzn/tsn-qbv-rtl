module tsn_qbv_config_change_time #(
  parameter int unsigned TickGranularityNs = 1
) (
  input  tsn_qbv_pkg::ptp_timestamp_t admin_base_time_i,
  input  tsn_qbv_pkg::cycle_time_ns_t admin_cycle_time_ns_i,
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  output tsn_qbv_pkg::ptp_timestamp_t config_change_time_o,
  output logic config_change_time_valid_o,
  output logic config_change_time_overflow_o
);

  import tsn_qbv_pkg::*;

  localparam ptp_time_ns_t NanosecondsPerSecond = 80'd1_000_000_000;
  localparam ptp_time_ns_t NanosecondsPerSecondMinusOne = 80'd999_999_999;
  localparam ptp_time_ns_t MaxPtpTimeNs =
      (ptp_time_ns_t'({48{1'b1}}) * NanosecondsPerSecond) +
      NanosecondsPerSecondMinusOne;

  ptp_time_ns_t admin_base_time_ns;
  ptp_time_ns_t current_time_ns;
  ptp_time_ns_t cycle_period_ns;
  ptp_time_ns_t cycle_delta_ns;
  ptp_time_ns_t cycle_remainder_ns;
  ptp_time_ns_t cycle_offset_ns;
  ptp_time_ns_t candidate_time_ns;
  logic [80:0] candidate_time_ns_extended;
  ptp_timestamp_t candidate_time;
  logic candidate_valid;
  logic candidate_overflow;

  assign admin_base_time_ns =
      (ptp_time_ns_t'(admin_base_time_i.seconds) * NanosecondsPerSecond) +
      ptp_time_ns_t'(admin_base_time_i.nanoseconds);
  assign current_time_ns =
      (ptp_time_ns_t'(current_time_i.seconds) * NanosecondsPerSecond) +
      ptp_time_ns_t'(current_time_i.nanoseconds);
  assign cycle_period_ns = ptp_time_ns_t'(admin_cycle_time_ns_i);

  always_comb begin
    cycle_delta_ns = '0;
    cycle_remainder_ns = '0;
    cycle_offset_ns = '0;
    candidate_time_ns = '0;
    candidate_time_ns_extended = '0;
    candidate_time = '0;
    candidate_valid = 1'b0;
    candidate_overflow = 1'b0;

    if ((TickGranularityNs > 0) &&
        (admin_base_time_i.nanoseconds < 32'd1_000_000_000) &&
        (current_time_i.nanoseconds < 32'd1_000_000_000) &&
        (cycle_period_ns != '0) &&
        ((cycle_period_ns % 80'(TickGranularityNs)) == '0) &&
        (((admin_base_time_ns >= current_time_ns)
              ? (admin_base_time_ns - current_time_ns)
              : (current_time_ns - admin_base_time_ns)) %
         80'(TickGranularityNs) == '0)) begin
      if (admin_base_time_ns >= current_time_ns) begin
        candidate_time = admin_base_time_i;
        candidate_valid = 1'b1;
      end else begin
        cycle_delta_ns = current_time_ns - admin_base_time_ns;
        cycle_remainder_ns = cycle_delta_ns % cycle_period_ns;
        if (cycle_remainder_ns != '0) begin
          cycle_offset_ns = cycle_period_ns - cycle_remainder_ns;
        end

        candidate_time_ns_extended =
            81'(current_time_ns) + 81'(cycle_offset_ns);
        if (candidate_time_ns_extended > 81'(MaxPtpTimeNs)) begin
          candidate_overflow = 1'b1;
        end else begin
          candidate_time_ns = candidate_time_ns_extended[79:0];
          candidate_time.seconds = 48'(candidate_time_ns / NanosecondsPerSecond);
          candidate_time.nanoseconds = 32'(candidate_time_ns % NanosecondsPerSecond);
          candidate_valid = 1'b1;
        end
      end
    end
  end

  assign config_change_time_o = candidate_valid ? candidate_time : '0;
  assign config_change_time_valid_o = candidate_valid;
  assign config_change_time_overflow_o = candidate_overflow;

`ifndef SYNTHESIS
  initial begin
    assert (TickGranularityNs > 0)
      else $fatal(1, "TickGranularityNs must be positive");
  end
`endif

endmodule : tsn_qbv_config_change_time
