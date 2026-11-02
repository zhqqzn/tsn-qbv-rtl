module tsn_qbv_tb;

  import tsn_qbv_pkg::*;

  localparam int unsigned GclDepth = 4;
  localparam int unsigned GclAddressWidth = $clog2(GclDepth);
  localparam int unsigned GclLengthWidth = $clog2(GclDepth + 1);
  localparam tsn_qbv_admin_config_t ResetAdminConfig = '{
    schedule: '{
      base_time: '0,
      cycle_time_ns: '0,
      cycle_time_extension_ns: '0
    },
    admin_gate_states: '1
  };

  logic clk_i;
  logic rst_ni;
  logic gate_enabled_i;
  logic config_change_set_i;
  ptp_timestamp_t current_time_i;
  logic admin_config_write_valid_i;
  logic admin_config_write_ready_o;
  tsn_qbv_admin_config_t admin_config_write_data_i;
  logic admin_config_write_error_o;
  logic admin_config_write_done_o;
  logic admin_config_valid_o;
  tsn_qbv_admin_config_t admin_config_o;
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
  logic time_tick_i;

  logic config_change_o;
  logic config_pending_o;
  ptp_timestamp_t config_change_time_o;
  logic config_change_time_valid_o;
  logic config_change_time_overflow_o;
  logic [63:0] config_change_error_o;
  logic oper_commit_o;
  logic new_config_ct_o;
  logic new_config_ct_ack_o;
  ptp_timestamp_t oper_base_time_o;
  cycle_time_ns_t oper_cycle_time_ns_o;
  logic [31:0] oper_cycle_time_extension_ns_o;
  logic [GclLengthWidth-1:0] admin_control_list_length_o;
  logic [GclLengthWidth-1:0] oper_control_list_length_o;
  gate_state_t oper_gate_states_o;
  logic [GclLengthWidth-1:0] list_pointer_o;
  logic list_active_o;
  logic list_complete_o;
  logic cycle_start_o;
  logic cycle_start_time_valid_o;
  ptp_timestamp_t cycle_start_time_o;

  tsn_qbv #(
    .GclDepth(GclDepth),
    .TickGranularityNs(2)
  ) dut (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .config_change_set_i,
    .current_time_i,
    .admin_config_write_valid_i,
    .admin_config_write_ready_o,
    .admin_config_write_data_i,
    .admin_config_write_error_o,
    .admin_config_write_done_o,
    .admin_config_valid_o,
    .admin_config_o,
    .admin_entry_write_valid_i,
    .admin_write_ready_o,
    .admin_entry_write_address_i,
    .admin_entry_write_data_i,
    .admin_length_write_valid_i,
    .admin_length_write_data_i,
    .admin_write_error_o,
    .time_tick_i,
    .config_change_o,
    .config_pending_o,
    .config_change_time_o,
    .config_change_time_valid_o,
    .config_change_time_overflow_o,
    .config_change_error_o,
    .oper_commit_o,
    .new_config_ct_o,
    .new_config_ct_ack_o,
    .oper_base_time_o,
    .oper_cycle_time_ns_o,
    .oper_cycle_time_extension_ns_o,
    .admin_control_list_length_o,
    .oper_control_list_length_o,
    .oper_gate_states_o,
    .list_pointer_o,
    .list_active_o,
    .list_complete_o,
    .cycle_start_o,
    .cycle_start_time_valid_o,
    .cycle_start_time_o,
    .admin_entry_write_done_o,
    .admin_entry_write_error_o,
    .admin_length_write_done_o,
    .admin_length_write_error_o
  );

  always #5ns clk_i = ~clk_i;

  task automatic step_clock;
    @(posedge clk_i);
    #1ps;
  endtask

  task automatic reject_admin_config(
    input tsn_qbv_admin_config_t config_data,
    input tsn_qbv_admin_config_t expected_admin_config,
    input logic expected_admin_valid
  );
    @(negedge clk_i);
    admin_config_write_valid_i = 1'b1;
    admin_config_write_data_i = config_data;
    #1ps;
    if (!admin_config_write_ready_o) begin
      $fatal(1, "Invalid Admin configuration could not be submitted");
    end
    step_clock();
    admin_config_write_valid_i = 1'b0;
    #1ps;
    if (!admin_config_write_done_o || !admin_config_write_error_o ||
        admin_config_o !== expected_admin_config ||
        admin_config_valid_o !== expected_admin_valid) begin
      $fatal(1, "Invalid Admin configuration changed the stored image or validity");
    end
  endtask

  task automatic write_admin_config(input tsn_qbv_admin_config_t config_data);
    @(negedge clk_i);
    admin_config_write_valid_i = 1'b1;
    admin_config_write_data_i = config_data;
    #1ps;
    if (!admin_config_write_ready_o) begin
      $fatal(1, "Admin configuration write was not ready");
    end
    step_clock();
    admin_config_write_valid_i = 1'b0;
    #1ps;
    if (!admin_config_write_done_o || admin_config_write_error_o ||
        admin_config_o !== config_data) begin
      $fatal(1, "Valid Admin configuration write was rejected");
    end
  endtask

  task automatic write_admin_entry(
    input logic [GclAddressWidth-1:0] address,
    input oper_gcl_entry_t entry
  );
    @(negedge clk_i);
    admin_entry_write_valid_i = 1'b1;
    admin_entry_write_address_i = address;
    admin_entry_write_data_i = entry;
    #1ps;
    if (!admin_write_ready_o) begin
      $fatal(1, "Admin GCL write was not ready");
    end
    step_clock();
    admin_entry_write_valid_i = 1'b0;
    #1ps;
    if (!admin_entry_write_done_o || admin_entry_write_error_o) begin
      $fatal(1, "Valid Admin GCL entry did not complete successfully");
    end
  endtask

  task automatic write_admin_length(input logic [GclLengthWidth-1:0] length);
    @(negedge clk_i);
    admin_length_write_valid_i = 1'b1;
    admin_length_write_data_i = length;
    #1ps;
    if (!admin_write_ready_o) begin
      $fatal(1, "Admin GCL length write was not ready");
    end
    step_clock();
    admin_length_write_valid_i = 1'b0;
    #1ps;
    if (!admin_length_write_done_o ||
        admin_length_write_error_o !== admin_write_error_o) begin
      $fatal(1, "Admin GCL length completion/error result was not reported");
    end
    if (admin_write_error_o) begin
      $fatal(1, "Valid Admin GCL length was rejected");
    end
  endtask

  task automatic advance_one_tick;
    @(negedge clk_i);
    current_time_i.nanoseconds = current_time_i.nanoseconds + 32'd2;
    time_tick_i = 1'b1;
    #1ps;
    step_clock();
    time_tick_i = 1'b0;
    #1ps;
  endtask

  initial begin
    clk_i = 1'b0;
    // Two-state simulation variables start at zero, so drive reset high first
    // and create a real falling edge to exercise asynchronous reset logic.
    rst_ni = 1'b1;
    gate_enabled_i = 1'b0;
    config_change_set_i = 1'b0;
    current_time_i = '{seconds: 48'd0, nanoseconds: 32'd100};
    admin_config_write_valid_i = 1'b0;
    admin_config_write_data_i = '0;
    admin_entry_write_valid_i = 1'b0;
    admin_entry_write_address_i = '0;
    admin_entry_write_data_i = '0;
    admin_length_write_valid_i = 1'b0;
    admin_length_write_data_i = '0;
    time_tick_i = 1'b0;

    #1ps;
    rst_ni = 1'b0;
    #1ps;
    if (admin_write_ready_o !== 1'b0 || admin_config_write_ready_o !== 1'b0 ||
        admin_config_o !== ResetAdminConfig || admin_config_valid_o ||
        admin_config_write_done_o || admin_entry_write_done_o || admin_entry_write_error_o ||
        config_pending_o !== 1'b0 ||
        config_change_o !== 1'b0 || config_change_error_o !== 64'd0 ||
        oper_cycle_time_ns_o !== '0 || oper_cycle_time_extension_ns_o !== '0 ||
        cycle_start_time_valid_o !== 1'b0 || list_complete_o !== 1'b0) begin
      $fatal(1, "Reset did not establish an idle Qbv core");
    end
    repeat (2) step_clock();
    @(negedge clk_i);
    rst_ni = 1'b1;
    step_clock();

    // An enabled request cannot be accepted against the reset-invalid Admin image.
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_change_set_i = 1'b1;
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (!config_change_o || config_pending_o || oper_commit_o || cycle_start_o ||
        admin_config_valid_o) begin
      $fatal(1, "ConfigChange was accepted before a valid Admin image existed");
    end

    // Reject a BaseTime outside the current timebase phase and an extension
    // that cannot be represented by the configured two-nanosecond tick.
    reject_admin_config(
      '{
        schedule: '{
          base_time: '{seconds: 48'd0, nanoseconds: 32'd101},
          cycle_time_ns: 64'd4,
          cycle_time_extension_ns: 32'd2
        },
        admin_gate_states: 8'hFF
      },
      ResetAdminConfig,
      1'b0
    );
    reject_admin_config(
      '{
        schedule: '{
          base_time: '{seconds: 48'd0, nanoseconds: 32'd100},
          cycle_time_ns: 64'd4,
          cycle_time_extension_ns: 32'd3
        },
        admin_gate_states: 8'hFF
      },
      ResetAdminConfig,
      1'b0
    );
    reject_admin_config(
      '{
        schedule: '{
          base_time: '{seconds: 48'd0, nanoseconds: 32'd100},
          cycle_time_ns: 64'd3,
          cycle_time_extension_ns: 32'd2
        },
        admin_gate_states: 8'hFF
      },
      ResetAdminConfig,
      1'b0
    );

    write_admin_entry(2'd0, '{gate_states: 8'h11, interval_ticks: 32'd3});
    write_admin_entry(2'd1, '{gate_states: 8'h22, interval_ticks: 32'd5});
    write_admin_length(3'd2);

    write_admin_config('{
      schedule: '{
        base_time: '{seconds: 48'd0, nanoseconds: 32'd100},
        cycle_time_ns: 64'd8,
        cycle_time_extension_ns: 32'd0
      },
      admin_gate_states: 8'hFF
    });
    if (!admin_config_valid_o) begin
      $fatal(1, "A valid Admin image was not marked valid");
    end

    // The valid Admin image releases the previously latched ConfigChange.
    // List Execute must see the commit bypass, not the previous empty Oper list.
    @(negedge clk_i);
    #1ps;
    if (!config_pending_o || !oper_commit_o || !new_config_ct_o ||
        !new_config_ct_ack_o || !cycle_start_o || admin_write_ready_o ||
        !config_change_o || admin_config_write_ready_o ||
        config_change_time_o != '{seconds: 48'd0, nanoseconds: 32'd100} ||
        !config_change_time_valid_o || config_change_time_overflow_o ||
        config_change_error_o != 64'd0 || admin_control_list_length_o != 3'd2) begin
      $fatal(1, "Immediate configuration commit did not form one atomic handoff");
    end
    if (oper_control_list_length_o != 3'd2) begin
      $fatal(1, "Commit bypass did not publish the new Oper length");
    end
    step_clock();
    config_change_set_i = 1'b0;
    #1ps;
    if (config_change_o || config_pending_o || oper_commit_o || new_config_ct_o ||
        !list_active_o || list_complete_o || list_pointer_o != 3'd0 ||
        oper_gate_states_o != 8'h11 ||
        oper_base_time_o != admin_config_o.schedule.base_time ||
        oper_cycle_time_ns_o != 64'd8 || oper_cycle_time_extension_ns_o != 32'd0 ||
        !cycle_start_time_valid_o ||
        cycle_start_time_o != '{seconds: 48'd0, nanoseconds: 32'd108}) begin
      $fatal(1, "First CycleStart did not execute entry zero from the committed schedule");
    end

    advance_one_tick();
    advance_one_tick();
    advance_one_tick();
    if (!list_active_o || list_pointer_o != 3'd1 || oper_gate_states_o != 8'h22) begin
      $fatal(1, "List Execute did not advance to entry one after three ticks");
    end

    reject_admin_config(
      '{
        schedule: '{
          base_time: '{seconds: 48'd0, nanoseconds: 32'd101},
          cycle_time_ns: 64'd6,
          cycle_time_extension_ns: 32'd0
        },
        admin_gate_states: 8'h00
      },
      '{
        schedule: '{
          base_time: '{seconds: 48'd0, nanoseconds: 32'd100},
          cycle_time_ns: 64'd8,
          cycle_time_extension_ns: 32'd0
        },
        admin_gate_states: 8'hFF
      },
      1'b1
    );

    advance_one_tick();
    if (!list_active_o || list_pointer_o != 3'd0 || oper_gate_states_o != 8'h11) begin
      $fatal(1, "A new CycleStart did not restart List Execute at entry zero");
    end

    // A dynamic update with a past AdminBaseTime must keep the old schedule
    // through its next cycle boundary, then atomically install the new image.
    advance_one_tick();
    advance_one_tick();
    advance_one_tick();
    if (!list_active_o || list_pointer_o != 3'd1 || oper_gate_states_o != 8'h22) begin
      $fatal(1, "Old schedule did not remain active before dynamic reconfiguration");
    end

    write_admin_entry(2'd0, '{gate_states: 8'h55, interval_ticks: 32'd2});
    write_admin_length(3'd1);
    write_admin_config('{
      schedule: '{
        base_time: '{seconds: 48'd0, nanoseconds: 32'd100},
        cycle_time_ns: 64'd10,
        cycle_time_extension_ns: 32'd0
      },
      admin_gate_states: 8'hFF
    });

    @(negedge clk_i);
    config_change_set_i = 1'b1;
    #1ps;
    if (!config_pending_o || admin_write_ready_o !== 1'b0 || oper_commit_o ||
        config_change_time_o != '{seconds: 48'd0, nanoseconds: 32'd120} ||
        !config_change_time_valid_o || config_change_time_overflow_o) begin
      $fatal(1, "Dynamic ConfigChange was not accepted with its scheduled target");
    end
    step_clock();
    config_change_set_i = 1'b0;
    if (config_change_error_o !== 64'd1) begin
      $fatal(1, "Past AdminBaseTime did not increment ConfigChangeError");
    end

    @(negedge clk_i);
    admin_config_write_valid_i = 1'b1;
    admin_config_write_data_i = '{
      schedule: '{
        base_time: '{seconds: 48'd0, nanoseconds: 32'd200},
        cycle_time_ns: 64'd12,
        cycle_time_extension_ns: 32'd0
      },
      admin_gate_states: 8'hAA
    };
    #1ps;
    if (admin_config_write_ready_o || admin_write_ready_o) begin
      $fatal(1, "Admin writes remained ready while ConfigPending was asserted");
    end

    @(negedge clk_i);
    current_time_i.nanoseconds = current_time_i.nanoseconds + 32'd2;
    time_tick_i = 1'b1;
    #1ps;
    if (!cycle_start_o || oper_commit_o || !config_pending_o ||
        config_change_time_o != '{seconds: 48'd0, nanoseconds: 32'd120} ||
        !config_change_time_valid_o || config_change_time_overflow_o) begin
      $fatal(1, "Old schedule did not preserve the accepted ConfigChangeTime");
    end
    step_clock();
    time_tick_i = 1'b0;
    #1ps;
    if (!list_active_o || list_pointer_o != 3'd0 || oper_gate_states_o != 8'h11 ||
        cycle_start_time_o != '{seconds: 48'd0, nanoseconds: 32'd120}) begin
      $fatal(1, "Old Oper schedule was not preserved until ConfigChangeTime");
    end

    advance_one_tick();
    @(negedge clk_i);
    current_time_i.nanoseconds = current_time_i.nanoseconds + 32'd2;
    time_tick_i = 1'b1;
    #1ps;
    if (!cycle_start_o || !oper_commit_o || !new_config_ct_o ||
        !new_config_ct_ack_o || oper_control_list_length_o != 3'd1) begin
      $fatal(1, "Dynamic Oper commit and CycleStart were not atomic");
    end
    step_clock();
    time_tick_i = 1'b0;
    #1ps;
    if (config_pending_o || new_config_ct_o || !list_active_o ||
        list_pointer_o != 3'd0 || oper_gate_states_o != 8'h55 ||
        oper_base_time_o != '{seconds: 48'd0, nanoseconds: 32'd100} ||
        oper_cycle_time_ns_o != 64'd10 ||
        admin_config_o.schedule.base_time != '{seconds: 48'd0, nanoseconds: 32'd100} ||
        admin_config_o.schedule.cycle_time_ns != 64'd10 ||
        cycle_start_time_o != '{seconds: 48'd0, nanoseconds: 32'd130}) begin
      $fatal(1, "Dynamic schedule was not activated as one coherent Oper image");
    end
    if (config_change_time_o != '{seconds: 48'd0, nanoseconds: 32'd120} ||
        !config_change_time_valid_o || config_change_time_overflow_o) begin
      $fatal(1, "Idle ConfigChangeTime candidate did not reflect the current Admin schedule");
    end

    // The held Admin write is accepted after the pending transaction commits.
    advance_one_tick();
    if (config_change_time_o != '{seconds: 48'd0, nanoseconds: 32'd200} ||
        !config_change_time_valid_o || config_change_time_overflow_o) begin
      $fatal(1, "Idle ConfigChangeTime status did not track the accepted Admin image");
    end
    admin_config_write_valid_i = 1'b0;
    #1ps;
    if (admin_config_write_error_o ||
        admin_config_o.schedule.base_time != '{seconds: 48'd0, nanoseconds: 32'd200} ||
        admin_config_o.schedule.cycle_time_ns != 64'd12 ||
        admin_config_o.admin_gate_states != 8'hAA ||
        oper_base_time_o != '{seconds: 48'd0, nanoseconds: 32'd100} ||
        oper_cycle_time_ns_o != 64'd10) begin
      $fatal(1, "Held Admin write did not update only the Admin image after commit");
    end

    // A request latched while disabled must snapshot the latest Admin image
    // when GateEnabled later accepts it.
    @(negedge clk_i);
    gate_enabled_i = 1'b0;
    step_clock();
    if (oper_gate_states_o != 8'hAA) begin
      $fatal(1, "AdminGateStates was not applied when GateEnabled became false");
    end
    config_change_set_i = 1'b1;
    step_clock();
    config_change_set_i = 1'b0;
    if (!config_change_o || config_pending_o) begin
      $fatal(1, "Disabled ConfigChange was not retained as a request latch");
    end

    write_admin_config('{
      schedule: '{
        base_time: '{seconds: 48'd0, nanoseconds: 32'd122},
        cycle_time_ns: 64'd14,
        cycle_time_extension_ns: 32'd0
      },
      admin_gate_states: 8'h5A
    });
    step_clock();
    if (oper_gate_states_o != 8'h5A ||
        oper_cycle_time_ns_o != 64'd10) begin
      $fatal(1, "Disabled AdminGateStates update changed the Oper schedule incorrectly");
    end
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    #1ps;
    if (!config_pending_o || !oper_commit_o || !new_config_ct_o ||
        !new_config_ct_ack_o || !cycle_start_o || !config_change_o ||
        !config_change_time_valid_o || config_change_time_overflow_o) begin
      $fatal(1, "Latched ConfigChange did not accept the latest Admin image");
    end
    step_clock();
    #1ps;
    if (config_change_o || config_pending_o ||
        oper_base_time_o != admin_config_o.schedule.base_time ||
        oper_cycle_time_ns_o != 64'd14 || !list_active_o ||
        oper_gate_states_o != 8'h55) begin
      $fatal(1, "Latest Admin image was not committed after disabled request");
    end

    // Assert reset away from a clock edge after the core has entered an active
    // schedule. This checks asynchronous reset, not just time-zero defaults.
    #1ps;
    rst_ni = 1'b0;
    #1ps;
    if (admin_config_write_ready_o !== 1'b0 || admin_write_ready_o !== 1'b0 ||
        admin_config_o !== ResetAdminConfig || admin_config_valid_o !== 1'b0 ||
        config_pending_o !== 1'b0 || config_change_o !== 1'b0 ||
        config_change_error_o !== 64'd0 || config_change_time_valid_o !== 1'b0 ||
        config_change_time_overflow_o !== 1'b0 || oper_base_time_o !== '0 ||
        oper_cycle_time_ns_o !== '0 || oper_cycle_time_extension_ns_o !== '0 ||
        oper_control_list_length_o !== '0 || list_active_o !== 1'b0 ||
        list_complete_o !== 1'b0 || list_pointer_o !== '0 ||
        oper_gate_states_o !== '1 || cycle_start_o !== 1'b0 ||
        cycle_start_time_valid_o !== 1'b0) begin
      $fatal(1, "Asynchronous reset did not restore the idle Qbv core");
    end

    $display("PASS: tsn_qbv atomic configuration and cycle execution integration");
    $finish;
  end

endmodule : tsn_qbv_tb
