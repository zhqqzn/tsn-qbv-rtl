module tsn_qbv_cycle_timer #(
  parameter int unsigned TickGranularityNs = 1
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic gate_enabled_i,
  input  logic config_pending_i,
  input  tsn_qbv_pkg::ptp_timestamp_t config_change_time_i,
  input  logic new_config_ct_i,

  // During NewConfigCT, these inputs expose the Oper image being committed.
  // The owner must provide the same-cycle commit bypass used by List Execute.
  input  tsn_qbv_pkg::cycle_time_ns_t oper_cycle_time_ns_i,
  input  logic [31:0] oper_cycle_time_extension_ns_i,
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,

  output logic cycle_start_o,
  output logic cycle_start_time_valid_o,
  output tsn_qbv_pkg::ptp_timestamp_t cycle_start_time_o,
  output logic new_config_ct_ack_o
);

  import tsn_qbv_pkg::*;

  localparam ptp_time_ns_t NanosecondsPerSecond = 80'd1_000_000_000;
  localparam ptp_time_ns_t NanosecondsPerSecondMinusOne = 80'd999_999_999;
  localparam ptp_time_ns_t MaxPtpTimeNs =
      (ptp_time_ns_t'({48{1'b1}}) * NanosecondsPerSecond) +
      NanosecondsPerSecondMinusOne;

  typedef enum logic {
    StDisabled,
    StWaiting
  } state_e;

  state_e state_q, state_d;

  ptp_time_ns_t current_time_ns;
  ptp_time_ns_t config_change_time_ns;
  ptp_time_ns_t cycle_start_time_ns_q, cycle_start_time_ns_d;
  ptp_time_ns_t next_phase_time_ns_q, next_phase_time_ns_d;
  ptp_time_ns_t candidate_cycle_start_time_ns;
  ptp_time_ns_t phase_at_or_after_current_ns;
  ptp_time_ns_t selection_threshold_ns;
  ptp_time_ns_t last_observed_time_ns_q;
  logic last_observed_time_valid_q;
  cycle_time_ns_t cycle_time_ns_q, cycle_time_ns_d;
  logic [31:0] cycle_time_extension_ns_q, cycle_time_extension_ns_d;
  logic phase_valid_q, phase_valid_d;
  logic cycle_start_time_valid_q, cycle_start_time_valid_d;
  logic cycle_start_is_config_q, cycle_start_is_config_d;
  logic cycle_start_is_config_candidate;

  function automatic ptp_time_ns_t timestamp_to_nanoseconds(
    input ptp_timestamp_t timestamp
  );
    ptp_time_ns_t seconds_ns;
    seconds_ns = ptp_time_ns_t'(timestamp.seconds) * NanosecondsPerSecond;
    return seconds_ns + ptp_time_ns_t'(timestamp.nanoseconds);
  endfunction

  function automatic ptp_timestamp_t nanoseconds_to_timestamp(
    input ptp_time_ns_t timestamp_ns
  );
    ptp_timestamp_t timestamp;
    timestamp.seconds = 48'(timestamp_ns / NanosecondsPerSecond);
    timestamp.nanoseconds = 32'(timestamp_ns % NanosecondsPerSecond);
    return timestamp;
  endfunction

  assign current_time_ns = timestamp_to_nanoseconds(current_time_i);
  assign config_change_time_ns = timestamp_to_nanoseconds(config_change_time_i);

  // SetCycleStartTime() is evaluated only when the Cycle Timer enters its
  // waiting state or after a CycleStart. The resulting target is registered
  // and remains stable until it is reached or a NewConfigCT restarts the timer.
  // ConfigChangeTime is already aligned to the committed OperBaseTime phase;
  // the accumulator therefore needs no variable-width division.
  always_comb begin
    phase_at_or_after_current_ns = next_phase_time_ns_q;
    if (phase_valid_q && (current_time_ns > next_phase_time_ns_q)) begin
      phase_at_or_after_current_ns = next_phase_time_ns_d;
    end

    candidate_cycle_start_time_ns = '0;
    cycle_start_is_config_candidate = 1'b0;
    selection_threshold_ns = current_time_ns +
                             ptp_time_ns_t'(cycle_time_ns_q) +
                             ptp_time_ns_t'(cycle_time_extension_ns_q);

    if (config_pending_i) begin
      if (!phase_valid_q ||
          (config_change_time_ns <= selection_threshold_ns)) begin
        candidate_cycle_start_time_ns = config_change_time_ns;
        cycle_start_is_config_candidate = 1'b1;
      end else begin
        candidate_cycle_start_time_ns = phase_at_or_after_current_ns;
      end
    end else if (phase_valid_q) begin
      candidate_cycle_start_time_ns = phase_at_or_after_current_ns;
    end
  end

  // NewConfigCT is a direct restart at ConfigChangeTime. It may interrupt a
  // previously selected old-cycle boundary; exact List Config equality
  // guarantees the handoff and Oper commit occur at this timestamp.
  assign cycle_start_time_valid_o = gate_enabled_i &&
                                    (new_config_ct_i || cycle_start_time_valid_q);
  assign cycle_start_time_o = !cycle_start_time_valid_o
                                  ? '0
                                  : (new_config_ct_i
                                         ? config_change_time_i
                                         : nanoseconds_to_timestamp(cycle_start_time_ns_q));
  assign cycle_start_o = gate_enabled_i &&
                         ((new_config_ct_i &&
                           (config_change_time_ns == current_time_ns)) ||
                          (state_q == StWaiting && cycle_start_time_valid_q &&
                           !cycle_start_is_config_q &&
                           (cycle_start_time_ns_q <= current_time_ns)));
  assign new_config_ct_ack_o = new_config_ct_i && cycle_start_o;

  // The phase accumulator tracks the next OperBaseTime + N*OperCycleTime
  // boundary independently of whether a pending configuration temporarily
  // selects ConfigChangeTime instead. The List Config procedure guarantees
  // that NewConfigCT is raised on a boundary aligned to the committed
  // OperBaseTime, so that timestamp becomes the new accumulator's phase origin.
  // While disabled, a boundary equal to CurrentTime remains eligible for an
  // immediate start if GateEnabled is re-enabled at that exact timestamp; a
  // boundary strictly in the past is advanced.
  always_comb begin
    next_phase_time_ns_d = next_phase_time_ns_q;
    phase_valid_d = phase_valid_q;

    if (new_config_ct_ack_o) begin
      next_phase_time_ns_d = current_time_ns +
                             ptp_time_ns_t'(oper_cycle_time_ns_i);
      phase_valid_d = (next_phase_time_ns_d <= MaxPtpTimeNs);
    end else if (phase_valid_q &&
                 ((current_time_ns > next_phase_time_ns_q) ||
                  (gate_enabled_i && (current_time_ns == next_phase_time_ns_q)))) begin
      next_phase_time_ns_d = next_phase_time_ns_q + ptp_time_ns_t'(cycle_time_ns_q);
      phase_valid_d = (next_phase_time_ns_d <= MaxPtpTimeNs);
    end
  end

  always_comb begin
    state_d = state_q;
    cycle_start_time_ns_d = cycle_start_time_ns_q;
    cycle_start_time_valid_d = cycle_start_time_valid_q;
    cycle_start_is_config_d = cycle_start_is_config_q;
    cycle_time_ns_d = cycle_time_ns_q;
    cycle_time_extension_ns_d = cycle_time_extension_ns_q;

    if (!gate_enabled_i) begin
      state_d = StDisabled;
      cycle_start_time_valid_d = 1'b0;
      cycle_start_is_config_d = 1'b0;
    end else if (new_config_ct_ack_o) begin
      cycle_time_ns_d = oper_cycle_time_ns_i;
      cycle_time_extension_ns_d = oper_cycle_time_extension_ns_i;
      if ((current_time_ns + ptp_time_ns_t'(oper_cycle_time_ns_i)) <= MaxPtpTimeNs) begin
        // The new schedule's first cycle starts at ConfigChangeTime.
        cycle_start_time_ns_d = current_time_ns +
                                ptp_time_ns_t'(oper_cycle_time_ns_i);
        cycle_start_time_valid_d = 1'b1;
        cycle_start_is_config_d = 1'b0;
        state_d = StWaiting;
      end else begin
        cycle_start_time_valid_d = 1'b0;
        cycle_start_is_config_d = 1'b0;
        state_d = StDisabled;
      end
    end else begin
      if (state_q == StDisabled) begin
        if (candidate_cycle_start_time_ns <= MaxPtpTimeNs &&
            (config_pending_i || phase_valid_q)) begin
          cycle_start_time_ns_d = candidate_cycle_start_time_ns;
          cycle_start_time_valid_d = 1'b1;
          cycle_start_is_config_d = cycle_start_is_config_candidate;
          state_d = StWaiting;
        end
      end else if (state_q == StWaiting && cycle_start_o) begin
        // A normal cycle has completed. Select the following boundary using
        // the configuration state observed at this CycleStart transition.
        if (config_pending_i &&
            (config_change_time_ns <= selection_threshold_ns) &&
            (config_change_time_ns <= MaxPtpTimeNs)) begin
          cycle_start_time_ns_d = config_change_time_ns;
          cycle_start_is_config_d = 1'b1;
          cycle_start_time_valid_d = 1'b1;
          state_d = StWaiting;
        end else if (phase_valid_d && next_phase_time_ns_d <= MaxPtpTimeNs) begin
          // Continue from the scheduled phase, not from a potentially late
          // CurrentTime sample, so a late observation cannot shift the phase.
          cycle_start_time_ns_d = next_phase_time_ns_d;
          cycle_start_is_config_d = 1'b0;
          cycle_start_time_valid_d = 1'b1;
          state_d = StWaiting;
        end else begin
          cycle_start_time_valid_d = 1'b0;
          cycle_start_is_config_d = 1'b0;
          state_d = StDisabled;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StDisabled;
      cycle_start_time_ns_q <= '0;
      cycle_start_time_valid_q <= 1'b0;
      cycle_start_is_config_q <= 1'b0;
      cycle_time_ns_q <= '0;
      cycle_time_extension_ns_q <= '0;
      phase_valid_q <= 1'b0;
      next_phase_time_ns_q <= '0;
      last_observed_time_ns_q <= '0;
      last_observed_time_valid_q <= 1'b0;
    end else begin
      state_q <= state_d;
      cycle_start_time_ns_q <= cycle_start_time_ns_d;
      cycle_start_time_valid_q <= cycle_start_time_valid_d;
      cycle_start_is_config_q <= cycle_start_is_config_d;
      cycle_time_ns_q <= cycle_time_ns_d;
      cycle_time_extension_ns_q <= cycle_time_extension_ns_d;
      phase_valid_q <= phase_valid_d;
      next_phase_time_ns_q <= next_phase_time_ns_d;
      last_observed_time_ns_q <= current_time_ns;
      last_observed_time_valid_q <= 1'b1;
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (TickGranularityNs > 0)
      else $fatal(1, "TickGranularityNs must be positive");
  end

  always_ff @(posedge clk_i) begin
    assert (current_time_i.nanoseconds < 32'd1_000_000_000)
      else $fatal(1, "CurrentTime nanoseconds field is not normalized");
    if (last_observed_time_valid_q) begin
      assert (current_time_ns >= last_observed_time_ns_q)
        else $fatal(1, "CurrentTime must not move backwards");
      assert (((current_time_ns - last_observed_time_ns_q) %
               80'(TickGranularityNs)) == '0)
        else $fatal(1, "CurrentTime movement is not aligned to TickGranularity");
    end

    if (phase_valid_q) begin
      assert (cycle_time_ns_q != '0)
        else $fatal(1, "Cycle Timer phase has a zero OperCycleTime");
      assert ((cycle_time_ns_q % 64'(TickGranularityNs)) == '0)
        else $fatal(1, "OperCycleTime is not aligned to TickGranularity");
      assert ((cycle_time_extension_ns_q % 32'(TickGranularityNs)) == '0)
        else $fatal(1, "OperCycleTimeExtension is not aligned to TickGranularity");
      assert (current_time_ns <= next_phase_time_ns_q +
                                ptp_time_ns_t'(cycle_time_ns_q))
        else $fatal(1, "CurrentTime skipped more than one Oper cycle boundary");
    end

    if (config_pending_i) begin
      assert (config_change_time_i.nanoseconds < 32'd1_000_000_000)
        else $fatal(1, "ConfigChangeTime nanoseconds field is not normalized");
      assert (config_change_time_ns >= current_time_ns)
        else $fatal(1, "ConfigChangeTime must not precede CurrentTime");
      assert (((config_change_time_ns - current_time_ns) %
               80'(TickGranularityNs)) == '0)
        else $fatal(1, "ConfigChangeTime is not aligned to TickGranularity");
    end

    if (new_config_ct_i) begin
      assert (gate_enabled_i && config_pending_i)
        else $fatal(1, "NewConfigCT requires GateEnabled and ConfigPending");
      assert (config_change_time_ns == current_time_ns)
        else $fatal(1, "NewConfigCT must be presented at ConfigChangeTime");
      assert (oper_cycle_time_ns_i != '0)
        else $fatal(1, "Committed OperCycleTime must be positive");
      assert ((oper_cycle_time_ns_i % 64'(TickGranularityNs)) == '0)
        else $fatal(1, "Committed OperCycleTime is not aligned to TickGranularity");
      assert ((oper_cycle_time_extension_ns_i % 32'(TickGranularityNs)) == '0)
        else $fatal(1, "Committed OperCycleTimeExtension is not aligned to TickGranularity");
      assert (new_config_ct_ack_o)
        else $fatal(1, "Cycle Timer did not acknowledge NewConfigCT at ConfigChangeTime");
    end

    if (cycle_start_o) begin
      assert (gate_enabled_i && cycle_start_time_valid_o)
        else $fatal(1, "CycleStart requires a valid enabled timer");
      assert (cycle_start_time_ns_q <= current_time_ns || new_config_ct_i)
        else $fatal(1, "CycleStart must not precede CycleStartTime");
    end

    if (state_q == StWaiting && cycle_start_time_valid_q &&
        cycle_start_is_config_q &&
        (cycle_start_time_ns_q == current_time_ns)) begin
      assert (new_config_ct_i)
        else $fatal(1, "ConfigChangeTime target requires NewConfigCT");
    end

    if (gate_enabled_i && state_q == StWaiting && cycle_start_time_valid_q &&
        !cycle_start_is_config_q) begin
      assert ((cycle_start_time_ns_q >= current_time_ns) ||
              ((current_time_ns - cycle_start_time_ns_q) <=
               ptp_time_ns_t'(TickGranularityNs)))
        else $fatal(1, "CycleStartTime was missed by more than one TickGranularity");
    end
  end
`endif

endmodule : tsn_qbv_cycle_timer
