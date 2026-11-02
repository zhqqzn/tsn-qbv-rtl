module tsn_qbv_list_config_tb;

  import tsn_qbv_pkg::*;

  localparam int unsigned GclDepth = 4;
  localparam int unsigned GclAddressWidth = $clog2(GclDepth);
  localparam int unsigned GclLengthWidth = $clog2(GclDepth + 1);

  logic clk_i;
  logic rst_ni;
  logic gate_enabled_i;
  logic config_change_set_i;
  logic new_config_ct_ack_i;
  ptp_timestamp_t current_time_i;
  ptp_timestamp_t admin_base_time_i;
  ptp_timestamp_t config_change_time_candidate_i;
  logic config_change_o;
  logic config_pending_o;
  logic config_accept_o;
  logic new_config_ct_o;
  logic oper_commit_o;
  ptp_timestamp_t config_change_time_o;
  logic [63:0] config_change_error_o;

  logic admin_entry_write_valid_i;
  logic admin_write_ready_o;
  logic [GclAddressWidth-1:0] admin_entry_write_address_i;
  oper_gcl_entry_t admin_entry_write_data_i;
  logic admin_length_write_valid_i;
  logic [GclLengthWidth-1:0] admin_length_write_data_i;
  logic admin_write_error_o;
  logic admin_entry_write_done_o;
  logic admin_entry_write_error_o;
  logic admin_length_write_done_o;
  logic admin_length_write_error_o;
  logic [GclLengthWidth-1:0] admin_control_list_length_o;
  logic [GclLengthWidth-1:0] oper_control_list_length_o;
  oper_gcl_entry_t oper_control_list_o [GclDepth];

  tsn_qbv_list_config list_config (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .config_accept_ready_i(1'b1),
    .config_change_set_i,
    .new_config_ct_ack_i,
    .current_time_i,
    .admin_base_time_i,
    .config_change_time_candidate_i,
    .config_change_o,
    .config_pending_o,
    .config_accept_o,
    .new_config_ct_o,
    .oper_commit_o,
    .config_change_time_o,
    .config_change_error_o
  );

  tsn_qbv_gcl_store #(
    .GclDepth(GclDepth)
  ) gcl_store (
    .clk_i,
    .rst_ni,
    .config_pending_i(config_pending_o),
    .oper_commit_i(oper_commit_o),
    .admin_entry_write_valid_i,
    .admin_write_ready_o,
    .admin_entry_write_address_i,
    .admin_entry_write_data_i,
    .admin_length_write_valid_i,
    .admin_length_write_data_i,
    .admin_write_error_o,
    .admin_entry_write_done_o,
    .admin_entry_write_error_o,
    .admin_length_write_done_o,
    .admin_length_write_error_o,
    .admin_control_list_length_o,
    .oper_control_list_length_o,
    .oper_control_list_o
  );

  initial begin
    clk_i = 1'b0;
    forever #5ns clk_i = ~clk_i;
  end

  task automatic step_clock();
    @(posedge clk_i);
    #1ps;
  endtask

  task automatic write_admin_entry(
    input logic [GclAddressWidth-1:0] address,
    input oper_gcl_entry_t entry
  );
    @(negedge clk_i);
    admin_entry_write_address_i = address;
    admin_entry_write_data_i = entry;
    admin_entry_write_valid_i = 1'b1;
    #1ps;
    if (admin_write_ready_o !== 1'b1) begin
      $fatal(1, "Admin GCL entry write was not ready");
    end
    step_clock();
    admin_entry_write_valid_i = 1'b0;
    #1ps;
    if (!admin_entry_write_done_o ||
        admin_entry_write_error_o !== admin_write_error_o) begin
      $fatal(1, "Admin GCL entry completion/error result was not reported");
    end
  endtask

  task automatic write_admin_length(input logic [GclLengthWidth-1:0] length);
    @(negedge clk_i);
    admin_length_write_data_i = length;
    admin_length_write_valid_i = 1'b1;
    #1ps;
    if (admin_write_ready_o !== 1'b1) begin
      $fatal(1, "Admin GCL length write was not ready");
    end
    step_clock();
    admin_length_write_valid_i = 1'b0;
    #1ps;
    if (!admin_length_write_done_o ||
        admin_length_write_error_o !== admin_write_error_o) begin
      $fatal(1, "Admin GCL length completion/error result was not reported");
    end
  endtask

  task automatic acknowledge_new_config();
    @(negedge clk_i);
    new_config_ct_ack_i = 1'b1;
    #1ps;
    if (new_config_ct_o !== 1'b1) begin
      $fatal(1, "Cycle Timer acknowledgement was not associated with NewConfigCT");
    end
    step_clock();
    new_config_ct_ack_i = 1'b0;
    #1ps;
    if (new_config_ct_o !== 1'b0 || config_pending_o !== 1'b0) begin
      $fatal(1, "Cycle Timer acknowledgement did not complete Config handoff");
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    gate_enabled_i = 1'b0;
    config_change_set_i = 1'b0;
    new_config_ct_ack_i = 1'b0;
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    admin_base_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    config_change_time_candidate_i = '{seconds: 48'd100, nanoseconds: 32'd100};
    admin_entry_write_valid_i = 1'b0;
    admin_entry_write_address_i = '0;
    admin_entry_write_data_i = '0;
    admin_length_write_valid_i = 1'b0;
    admin_length_write_data_i = '0;

    // Reset must suppress both sides of the control-plane handshakes. A
    // request or write pulse during reset is not an accepted transaction.
    gate_enabled_i = 1'b1;
    config_change_set_i = 1'b1;
    new_config_ct_ack_i = 1'b1;
    config_change_time_candidate_i = current_time_i;
    admin_entry_write_valid_i = 1'b1;
    admin_entry_write_address_i = '0;
    admin_entry_write_data_i = '{gate_states: 8'hDE, interval_ticks: 32'd1};
    admin_length_write_valid_i = 1'b1;
    admin_length_write_data_i = GclLengthWidth'(1);
    #1ps;
    if (config_change_o !== 1'b0 || config_pending_o !== 1'b0 ||
        config_accept_o !== 1'b0 || new_config_ct_o !== 1'b0 ||
        oper_commit_o !== 1'b0 || admin_write_ready_o !== 1'b0) begin
      $fatal(1, "List Config or GCL storage exposed a handshake during reset");
    end
    repeat (2) step_clock();
    if (admin_control_list_length_o !== '0 || oper_control_list_length_o !== '0 ||
        config_change_error_o !== '0) begin
      $fatal(1, "Reset state or GCL storage state is incorrect");
    end

    gate_enabled_i = 1'b0;
    config_change_set_i = 1'b0;
    new_config_ct_ack_i = 1'b0;
    admin_entry_write_valid_i = 1'b0;
    admin_length_write_valid_i = 1'b0;
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    config_change_time_candidate_i = '{seconds: 48'd100, nanoseconds: 32'd100};
    #1ns;
    repeat (2) step_clock();
    if (config_change_o !== 1'b0 || config_pending_o !== 1'b0 ||
        config_accept_o !== 1'b0 || new_config_ct_o !== 1'b0 ||
        oper_commit_o !== 1'b0) begin
      $fatal(1, "List Config reset state is incorrect");
    end

    @(negedge clk_i);
    rst_ni = 1'b1;
    step_clock();

    write_admin_entry(2'd0, '{gate_states: 8'h11, interval_ticks: 32'd3});
    write_admin_length(3'd1);

    // A disabled request is retained but does not lock the Admin image.
    @(negedge clk_i);
    config_change_set_i = 1'b1;
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (config_change_o !== 1'b1 || config_pending_o !== 1'b0 ||
        config_accept_o !== 1'b0 || admin_write_ready_o !== 1'b1 ||
        config_change_error_o !== 64'd0) begin
      $fatal(1, "Disabled ConfigChange request was not retained");
    end

    write_admin_entry(2'd1, '{gate_states: 8'h22, interval_ticks: 32'd5});
    write_admin_length(3'd2);

    // Acceptance captures ConfigChangeTime and blocks all Admin writes.
    // A future AdminBaseTime is its own legal activation boundary.
    @(negedge clk_i);
    admin_base_time_i = '{seconds: 48'd100, nanoseconds: 32'd100};
    gate_enabled_i = 1'b1;
    admin_entry_write_valid_i = 1'b1;
    admin_entry_write_address_i = 2'd2;
    admin_entry_write_data_i = '{gate_states: 8'h44, interval_ticks: 32'd7};
    #1ps;
    if (config_accept_o !== 1'b1 || config_pending_o !== 1'b1 ||
        admin_write_ready_o !== 1'b0) begin
      $fatal(1, "ConfigChange acceptance did not lock Admin writes");
    end
    step_clock();
    admin_entry_write_valid_i = 1'b0;
    #1ps;
    if (config_change_o !== 1'b0 || config_pending_o !== 1'b1 ||
        config_accept_o !== 1'b0 || config_change_error_o !== 64'd0 ||
        admin_control_list_length_o !== 3'd2 ||
        admin_write_error_o !== 1'b0 ||
        config_change_time_o !== '{seconds: 48'd100, nanoseconds: 32'd100}) begin
      $fatal(1, "ConfigChange was not accepted atomically");
    end

    // Disabling GateEnabled before ConfigChangeTime cancels CONFIG_PENDING.
    @(negedge clk_i);
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd50};
    gate_enabled_i = 1'b0;
    step_clock();
    if (config_pending_o !== 1'b0 || oper_commit_o !== 1'b0 ||
        oper_control_list_length_o !== '0 || admin_write_ready_o !== 1'b1) begin
      $fatal(1, "GateEnabled falling before ConfigChangeTime did not cancel pending update");
    end

    // The accepted request was consumed on entry to CONFIG_PENDING. A new
    // request made while disabled is retained and accepted after re-enable.
    @(negedge clk_i);
    config_change_set_i = 1'b1;
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (config_change_o !== 1'b1 || config_pending_o !== 1'b0 ||
        admin_write_ready_o !== 1'b1) begin
      $fatal(1, "New disabled ConfigChange request was not retained");
    end

    @(negedge clk_i);
    admin_base_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    gate_enabled_i = 1'b1;
    #1ps;
    if (config_accept_o !== 1'b1 || config_pending_o !== 1'b1) begin
      $fatal(1, "Retained ConfigChange request was not accepted after re-enable");
    end
    step_clock();
    if (config_change_error_o !== 64'd1) begin
      $fatal(1, "Past AdminBaseTime did not increment ConfigChangeError exactly once");
    end

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd99};
    #1ps;
    if (new_config_ct_o !== 1'b0 || oper_commit_o !== 1'b0) begin
      $fatal(1, "ConfigChange activated before exact timestamp equality");
    end
    step_clock();

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd100};
    #1ps;
    if (new_config_ct_o !== 1'b1 || oper_commit_o !== 1'b1 ||
        config_pending_o !== 1'b1 || oper_control_list_length_o !== 3'd2) begin
      $fatal(1, "UPDATE_CONFIG did not commit Oper and assert NewConfigCT at exact time");
    end
    step_clock();
    #1ps;
    if (new_config_ct_o !== 1'b1 || oper_commit_o !== 1'b0 ||
        config_pending_o !== 1'b1 || oper_control_list_length_o !== 3'd2 ||
        oper_control_list_o[0] !== '{gate_states: 8'h11, interval_ticks: 32'd3} ||
        oper_control_list_o[1] !== '{gate_states: 8'h22, interval_ticks: 32'd5}) begin
      $fatal(1, "Oper image was not committed exactly once before Timer acknowledgement");
    end
    repeat (3) step_clock();
    if (new_config_ct_o !== 1'b1 || config_pending_o !== 1'b1 ||
        admin_write_ready_o !== 1'b0) begin
      $fatal(1, "NewConfigCT handoff was not held while Cycle Timer was busy");
    end
    acknowledge_new_config();
    if (admin_write_ready_o !== 1'b1) begin
      $fatal(1, "Admin writes did not resume after Timer acknowledgement");
    end

    // Timestamp equality compares both seconds and nanoseconds fields.
    write_admin_entry(2'd0, '{gate_states: 8'hA5, interval_ticks: 32'd9});
    @(negedge clk_i);
    admin_base_time_i = '{seconds: 48'd101, nanoseconds: 32'd10};
    config_change_time_candidate_i = '{seconds: 48'd101, nanoseconds: 32'd10};
    config_change_set_i = 1'b1;
    #1ps;
    if (config_accept_o !== 1'b1) begin
      $fatal(1, "Second ConfigChange request was not accepted");
    end
    step_clock();
    if (config_change_error_o !== 64'd1) begin
      $fatal(1, "Future AdminBaseTime incorrectly incremented ConfigChangeError");
    end
    config_change_set_i = 1'b0;

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd101, nanoseconds: 32'd9};
    #1ps;
    if (new_config_ct_o !== 1'b0 || oper_commit_o !== 1'b0) begin
      $fatal(1, "Timestamp comparison ignored nanoseconds");
    end
    step_clock();

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd101, nanoseconds: 32'd10};
    #1ps;
    if (new_config_ct_o !== 1'b1 || oper_commit_o !== 1'b1) begin
      $fatal(1, "Second UPDATE_CONFIG did not occur at exact timestamp");
    end
    step_clock();
    #1ps;
    if (oper_control_list_o[0].gate_states !== 8'hA5 ||
        oper_commit_o !== 1'b0 || config_pending_o !== 1'b1) begin
      $fatal(1, "Second Admin-to-Oper update was not committed");
    end
    acknowledge_new_config();

    // A ConfigChange whose target equals CurrentTime commits on acceptance.
    write_admin_entry(2'd0, '{gate_states: 8'h5A, interval_ticks: 32'd11});
    @(negedge clk_i);
    admin_base_time_i = current_time_i;
    config_change_time_candidate_i = current_time_i;
    config_change_set_i = 1'b1;
    #1ps;
    if (config_accept_o !== 1'b1 || config_pending_o !== 1'b1 ||
        new_config_ct_o !== 1'b1 || oper_commit_o !== 1'b1 ||
        admin_write_ready_o !== 1'b0) begin
      $fatal(1, "Immediate ConfigChange did not enter UPDATE_CONFIG atomically");
    end
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (config_pending_o !== 1'b1 || new_config_ct_o !== 1'b1 ||
        oper_commit_o !== 1'b0 || config_change_error_o !== 64'd1 ||
        oper_control_list_o[0].gate_states !== 8'h5A) begin
      $fatal(1, "Immediate Admin-to-Oper commit did not complete exactly once");
    end
    acknowledge_new_config();

    // Once UPDATE_CONFIG has committed, GateEnabled may clear the Timer handoff
    // but must not roll the already installed Oper image back to the old list.
    write_admin_entry(2'd0, '{gate_states: 8'hC3, interval_ticks: 32'd13});
    @(negedge clk_i);
    admin_base_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    config_change_time_candidate_i = '{seconds: 48'd101, nanoseconds: 32'd200};
    config_change_set_i = 1'b1;
    step_clock();
    config_change_set_i = 1'b0;
    if (config_change_error_o !== 64'd2) begin
      $fatal(1, "Past AdminBaseTime was not counted for the final configuration");
    end

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd101, nanoseconds: 32'd200};
    #1ps;
    if (oper_commit_o !== 1'b1 || new_config_ct_o !== 1'b1) begin
      $fatal(1, "Final UPDATE_CONFIG transition was not triggered");
    end
    step_clock();
    #1ps;
    if (oper_control_list_o[0].gate_states !== 8'hC3 || config_pending_o !== 1'b1) begin
      $fatal(1, "Final Oper image was not installed before Timer handoff");
    end

    @(negedge clk_i);
    gate_enabled_i = 1'b0;
    #1ps;
    if (new_config_ct_o !== 1'b0 || oper_commit_o !== 1'b0) begin
      $fatal(1, "GateEnabled falling did not suppress NewConfigCT");
    end
    step_clock();
    #1ps;
    if (config_pending_o !== 1'b0 || admin_write_ready_o !== 1'b1 ||
        oper_control_list_o[0].gate_states !== 8'hC3) begin
      $fatal(1, "GateEnabled drop after UPDATE_CONFIG rolled back Oper configuration");
    end

    // If GateEnabled is removed on the exact ConfigChangeTime edge, the
    // pending image is cancelled rather than committed without an enabled gate.
    @(negedge clk_i);
    admin_base_time_i = '{seconds: 48'd101, nanoseconds: 32'd300};
    config_change_time_candidate_i = '{seconds: 48'd101, nanoseconds: 32'd300};
    config_change_set_i = 1'b1;
    #1ps;
    if (config_change_o !== 1'b0 || config_pending_o !== 1'b0 ||
        config_accept_o !== 1'b0) begin
      $fatal(1, "Disabled ConfigChange request was not held before the boundary test");
    end
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (config_change_o !== 1'b1 || config_pending_o !== 1'b0) begin
      $fatal(1, "ConfigChange request was not retained while disabled");
    end

    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    #1ps;
    if (config_accept_o !== 1'b1 || config_pending_o !== 1'b1 ||
        oper_commit_o !== 1'b0) begin
      $fatal(1, "Retained ConfigChange was not accepted after re-enable");
    end
    step_clock();
    #1ps;
    if (config_pending_o !== 1'b1 ||
        config_change_time_o !== '{seconds: 48'd101, nanoseconds: 32'd300}) begin
      $fatal(1, "ConfigChangeTime was not captured for the boundary cancellation test");
    end

    @(negedge clk_i);
    current_time_i = '{seconds: 48'd101, nanoseconds: 32'd300};
    gate_enabled_i = 1'b0;
    #1ps;
    if (config_pending_o !== 1'b1 || oper_commit_o !== 1'b0 ||
        new_config_ct_o !== 1'b0) begin
      $fatal(1, "Disabling at ConfigChangeTime did not suppress the commit");
    end
    step_clock();
    #1ps;
    if (config_pending_o !== 1'b0 || config_change_o !== 1'b0 ||
        oper_commit_o !== 1'b0 || new_config_ct_o !== 1'b0 ||
        admin_write_ready_o !== 1'b1 ||
        oper_control_list_o[0].gate_states !== 8'hC3 ||
        config_change_error_o !== 64'd2) begin
      $fatal(1, "ConfigChange at the disable boundary changed the Oper image or remained pending");
    end

    $display("PASS: tsn_qbv_list_config and GCL storage directed tests");
    $finish;
  end

endmodule : tsn_qbv_list_config_tb
