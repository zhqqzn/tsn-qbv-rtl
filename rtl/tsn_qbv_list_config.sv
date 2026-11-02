module tsn_qbv_list_config (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic gate_enabled_i,
  input  logic config_accept_ready_i,
  input  logic config_change_set_i,
  input  logic new_config_ct_ack_i,
  input  tsn_qbv_pkg::ptp_timestamp_t current_time_i,
  input  tsn_qbv_pkg::ptp_timestamp_t admin_base_time_i,
  input  tsn_qbv_pkg::ptp_timestamp_t config_change_time_candidate_i,

  output logic config_change_o,
  output logic config_pending_o,
  output logic config_accept_o,
  output logic new_config_ct_o,
  output logic oper_commit_o,
  output tsn_qbv_pkg::ptp_timestamp_t config_change_time_o,
  output logic [63:0] config_change_error_o
);

  import tsn_qbv_pkg::*;

  typedef enum logic [1:0] {
    StConfigIdle,
    StConfigPending,
    StConfigUpdate
  } state_e;

  state_e state_q, state_d;
  logic config_change_q, config_change_d;
  logic config_update_now;
  logic admin_base_time_in_past;
  logic [63:0] config_change_error_q;
  ptp_timestamp_t config_change_time_q, config_change_time_d;

  // ConfigChange is a management request latch. A request made while the
  // state machines are disabled remains latched until GateEnabled accepts it.
  // The complete Admin image is locked from acceptance through the Cycle Timer
  // handoff acknowledgement.
  assign admin_base_time_in_past =
      (admin_base_time_i.seconds < current_time_i.seconds) ||
      ((admin_base_time_i.seconds == current_time_i.seconds) &&
       (admin_base_time_i.nanoseconds < current_time_i.nanoseconds));
  assign config_change_error_o = config_change_error_q;
  assign config_change_o = rst_ni && config_change_q;
  assign config_accept_o = rst_ni && (state_q == StConfigIdle) && gate_enabled_i &&
                           config_accept_ready_i &&
                           (config_change_q || config_change_set_i);
  assign config_pending_o = rst_ni && ((state_q != StConfigIdle) || config_accept_o);
  assign config_change_time_o = !rst_ni ? '0 :
                                (config_accept_o ? config_change_time_candidate_i :
                                                   config_change_time_q);

  // IEEE 802.1Q-2022 maintenance item 0319 changed the UPDATE_CONFIG trigger
  // to exact timestamp equality. Oper is committed at that transition, while
  // NewConfigCT remains asserted until Cycle Timer has captured the new timing
  // parameters. List Config has no dependency on CycleStart.
  assign config_update_now = rst_ni && gate_enabled_i &&
                             ((state_q == StConfigPending) || config_accept_o) &&
                             (current_time_i == config_change_time_o);
  assign oper_commit_o = config_update_now;
  assign new_config_ct_o = rst_ni && gate_enabled_i &&
                           (config_update_now || (state_q == StConfigUpdate));

  always_comb begin
    state_d = state_q;
    config_change_d = config_change_q;
    config_change_time_d = config_change_time_q;

    unique case (state_q)
      StConfigIdle: begin
        if (config_change_set_i) begin
          config_change_d = 1'b1;
        end
        if (config_accept_o) begin
          config_change_d = 1'b0;
          config_change_time_d = config_change_time_candidate_i;
          if (config_update_now) begin
            state_d = new_config_ct_ack_i ? StConfigIdle : StConfigUpdate;
          end else begin
            state_d = StConfigPending;
          end
        end
      end

      StConfigPending: begin
        if (!gate_enabled_i) begin
          // Before ConfigChangeTime, disabling GateEnabled cancels the update.
          state_d = StConfigIdle;
        end else if (config_update_now) begin
          state_d = new_config_ct_ack_i ? StConfigIdle : StConfigUpdate;
        end
      end

      StConfigUpdate: begin
        // The Admin-to-Oper copy has already happened. Disabling GateEnabled
        // clears the handoff, but does not roll back the committed Oper image.
        if (!gate_enabled_i || new_config_ct_ack_i) begin
          state_d = StConfigIdle;
        end
      end

      default: begin
        state_d = StConfigIdle;
        config_change_d = 1'b0;
        config_change_time_d = '0;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StConfigIdle;
      config_change_q <= 1'b0;
      config_change_time_q <= '0;
      config_change_error_q <= '0;
    end else begin
      state_q <= state_d;
      config_change_q <= config_change_d;
      config_change_time_q <= config_change_time_d;
      if (config_accept_o && admin_base_time_in_past) begin
        config_change_error_q <= config_change_error_q + 64'd1;
      end
    end
  end

endmodule : tsn_qbv_list_config
