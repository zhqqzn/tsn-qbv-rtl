module tsn_qbv_list_execute_tb;

  import tsn_qbv_pkg::*;

  localparam int unsigned GclDepth = 5;
  localparam int unsigned GclAddressWidth = $clog2(GclDepth);
  localparam int unsigned GclLengthWidth = $clog2(GclDepth + 1);
  localparam int unsigned ListPointerWidth = $clog2(GclDepth + 1);

  logic clk_i;
  logic rst_ni;
  logic gate_enabled_i;
  logic cycle_start_i;
  logic time_tick_i;
  gate_state_t admin_gate_states_i;

  logic config_pending_i;
  logic oper_commit_i;
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

  gate_state_t oper_gate_states_o;
  logic [ListPointerWidth-1:0] list_pointer_o;
  logic list_active_o;
  logic list_complete_o;

  tsn_qbv_gcl_store #(
    .GclDepth(GclDepth)
  ) gcl_store (
    .clk_i,
    .rst_ni,
    .config_pending_i,
    .oper_commit_i,
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

  tsn_qbv_list_execute #(
    .GclDepth(GclDepth)
  ) dut (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .cycle_start_i,
    .time_tick_i,
    .admin_gate_states_i,
    .oper_control_list_length_i(oper_control_list_length_o),
    .oper_control_list_i(oper_control_list_o),
    .oper_gate_states_o,
    .list_pointer_o,
    .list_active_o,
    .list_complete_o
  );

  initial begin
    clk_i = 1'b0;
    forever #5ns clk_i = ~clk_i;
  end

  task automatic step_clock();
    @(posedge clk_i);
    #1ps;
  endtask

  task automatic pulse_cycle_start();
    @(negedge clk_i);
    cycle_start_i = 1'b1;
    step_clock();
    cycle_start_i = 1'b0;
  endtask

  task automatic pulse_time_tick();
    @(negedge clk_i);
    time_tick_i = 1'b1;
    step_clock();
    time_tick_i = 1'b0;
  endtask

  task automatic pulse_cycle_start_and_tick();
    @(negedge clk_i);
    cycle_start_i = 1'b1;
    time_tick_i = 1'b1;
    step_clock();
    cycle_start_i = 1'b0;
    time_tick_i = 1'b0;
  endtask

  task automatic write_admin_entry(
    input logic [GclAddressWidth-1:0] address,
    input oper_gcl_entry_t entry
  );
    @(negedge clk_i);
    admin_entry_write_address_i = address;
    admin_entry_write_data_i = entry;
    admin_entry_write_valid_i = 1'b1;
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

  task automatic write_admin_entry_and_length(
    input logic [GclAddressWidth-1:0] address,
    input oper_gcl_entry_t entry,
    input logic [GclLengthWidth-1:0] length
  );
    @(negedge clk_i);
    admin_entry_write_address_i = address;
    admin_entry_write_data_i = entry;
    admin_entry_write_valid_i = 1'b1;
    admin_length_write_data_i = length;
    admin_length_write_valid_i = 1'b1;
    if (admin_write_ready_o !== 1'b1) begin
      $fatal(1, "Admin GCL entry and length writes were not ready");
    end
    step_clock();
    admin_entry_write_valid_i = 1'b0;
    admin_length_write_valid_i = 1'b0;
    #1ps;
    if (!admin_entry_write_done_o || !admin_length_write_done_o ||
        admin_entry_write_error_o !== admin_write_error_o ||
        admin_length_write_error_o !== admin_write_error_o) begin
      $fatal(1, "Simultaneous Admin GCL write results were not reported consistently");
    end
  endtask

  task automatic check_state(
    input gate_state_t expected_gates,
    input logic [ListPointerWidth-1:0] expected_pointer,
    input logic expected_active,
    input logic expected_complete,
    input string test_name
  );
    if (oper_gate_states_o !== expected_gates ||
        list_pointer_o !== expected_pointer ||
        list_active_o !== expected_active ||
        list_complete_o !== expected_complete) begin
      $fatal(1,
        "%s: gates=%02h pointer=%0d active=%0b complete=%0b",
        test_name, oper_gate_states_o, list_pointer_o, list_active_o, list_complete_o);
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    gate_enabled_i = 1'b0;
    cycle_start_i = 1'b0;
    time_tick_i = 1'b0;
    admin_gate_states_i = 8'hA5;

    config_pending_i = 1'b0;
    oper_commit_i = 1'b0;
    admin_entry_write_valid_i = 1'b0;
    admin_entry_write_address_i = '0;
    admin_entry_write_data_i = '0;
    admin_length_write_valid_i = 1'b0;
    admin_length_write_data_i = '0;

    #1ns;
    repeat (2) step_clock();
    check_state(8'hFF, '0, 1'b0, 1'b0, "reset");
    if (oper_control_list_length_o !== '0) begin
      $fatal(1, "Oper GCL length must reset to zero");
    end

    @(negedge clk_i);
    rst_ni = 1'b1;
    step_clock();
    check_state(8'hA5, '0, 1'b0, 1'b0, "INIT applies AdminGateStates");

    @(negedge clk_i);
    admin_gate_states_i = 8'h5A;
    step_clock();
    check_state(8'h5A, '0, 1'b0, 1'b0, "INIT tracks AdminGateStates");

    write_admin_entry(GclAddressWidth'(GclDepth),
      '{gate_states: 8'hEE, interval_ticks: 32'd1});
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "Out-of-range Admin GCL entry write was not rejected");
    end
    write_admin_length(GclLengthWidth'(GclDepth + 1));
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "Out-of-range Admin GCL length was not rejected");
    end

    // Publishing a length before every referenced entry is initialized must
    // fail. A final entry write and its length publication may share one edge.
    write_admin_length(GclLengthWidth'(3));
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "Uninitialized Admin GCL entries were published");
    end

    write_admin_entry(GclAddressWidth'(0), '{gate_states: 8'hFF, interval_ticks: 32'd0});
    if (admin_write_error_o !== 1'b1) begin
      $fatal(1, "Zero-length normalized GCL entry was accepted");
    end
    write_admin_length(GclLengthWidth'(1));
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "GCL length exposed an entry with a zero interval");
    end

    write_admin_entry(GclAddressWidth'(0), '{gate_states: 8'h01, interval_ticks: 32'd2});
    write_admin_length(GclLengthWidth'(3));
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "Partially initialized Admin GCL was published");
    end

    write_admin_entry(GclAddressWidth'(1), '{gate_states: 8'h02, interval_ticks: 32'd1});
    write_admin_entry_and_length(GclAddressWidth'(2),
      '{gate_states: 8'h04, interval_ticks: 32'd3}, GclLengthWidth'(3));
    if (admin_write_error_o !== 1'b0 ||
        admin_control_list_length_o !== GclLengthWidth'(3)) begin
      $fatal(1, "Fully initialized Admin GCL length was not stored");
    end
    if (oper_control_list_length_o !== '0) begin
      $fatal(1, "Admin writes must not change the Oper GCL before commit");
    end

    // Commit and CycleStart share one edge. List Execute must see the new
    // Admin image through the GCL store's commit bypass on this same edge.
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_pending_i = 1'b1;
    oper_commit_i = 1'b1;
    cycle_start_i = 1'b1;
    step_clock();
    config_pending_i = 1'b0;
    oper_commit_i = 1'b0;
    cycle_start_i = 1'b0;
    check_state(8'h01, '0, 1'b1, 1'b0, "atomic initial commit and CycleStart");
    if (oper_control_list_length_o !== GclLengthWidth'(3)) begin
      $fatal(1, "Oper GCL length did not commit atomically");
    end

    pulse_time_tick();
    check_state(8'h01, '0, 1'b1, 1'b0, "first entry remains active after one tick");
    pulse_time_tick();
    check_state(8'h02, ListPointerWidth'(1), 1'b1, 1'b0,
      "second GCL entry starts after two ticks");

    // CycleStart must preempt the old entry's coincident expiry tick. The
    // new first interval starts in full on the following timebase tick.
    pulse_cycle_start_and_tick();
    check_state(8'h01, '0, 1'b1, 1'b0,
      "CycleStart preempts simultaneous interval expiry");
    pulse_time_tick();
    check_state(8'h01, '0, 1'b1, 1'b0,
      "coincident time tick does not consume the new first interval");
    pulse_time_tick();
    check_state(8'h02, ListPointerWidth'(1), 1'b1, 1'b0,
      "new first interval expires after its full duration");

    // Prepare a replacement Admin image while the old Oper image is running.
    write_admin_entry(GclAddressWidth'(0), '{gate_states: 8'h11, interval_ticks: 32'd1});
    write_admin_entry(GclAddressWidth'(1), '{gate_states: 8'h22, interval_ticks: 32'd2});
    write_admin_length(GclLengthWidth'(2));
    if (oper_control_list_length_o !== GclLengthWidth'(3) ||
        oper_control_list_o[0].gate_states !== 8'h01 ||
        oper_control_list_o[1].gate_states !== 8'h02) begin
      $fatal(1, "Admin writes leaked into the active Oper image");
    end

    // A write presented while ConfigPending is high must not be accepted.
    @(negedge clk_i);
    config_pending_i = 1'b1;
    admin_entry_write_valid_i = 1'b1;
    admin_entry_write_address_i = '0;
    admin_entry_write_data_i = '{gate_states: 8'h80, interval_ticks: 32'd1};
    // Allow the combinational ready output to settle after changing its input.
    #1ps;
    if (admin_write_ready_o !== 1'b0) begin
      $fatal(1, "Admin write must be blocked while ConfigPending");
    end
    step_clock();

    // The locked write is still asserted during commit. The new Admin image
    // must become visible to List Execute on the same edge as CycleStart.
    @(negedge clk_i);
    oper_commit_i = 1'b1;
    cycle_start_i = 1'b1;
    step_clock();
    admin_entry_write_valid_i = 1'b0;
    config_pending_i = 1'b0;
    oper_commit_i = 1'b0;
    cycle_start_i = 1'b0;
    check_state(8'h11, '0, 1'b1, 1'b0, "atomic replacement commit and CycleStart");
    if (oper_control_list_length_o !== GclLengthWidth'(2) ||
        oper_control_list_o[0].gate_states !== 8'h11) begin
      $fatal(1, "replacement Admin image was not committed");
    end

    pulse_time_tick();
    check_state(8'h22, ListPointerWidth'(1), 1'b1, 1'b0,
      "replacement second entry starts after one tick");
    repeat (2) pulse_time_tick();
    check_state(8'h22, ListPointerWidth'(2), 1'b0, 1'b1,
      "last gate state holds after list completion");

    @(negedge clk_i);
    gate_enabled_i = 1'b0;
    step_clock();
    check_state(8'h5A, '0, 1'b0, 1'b0, "GateEnabled low enters INIT");

    @(negedge clk_i);
    admin_gate_states_i = 8'hC3;
    step_clock();
    check_state(8'hC3, '0, 1'b0, 1'b0, "disabled INIT applies updated AdminGateStates");

    pulse_cycle_start();
    check_state(8'hC3, '0, 1'b0, 1'b0, "CycleStart is ignored while disabled");

    write_admin_length('0);
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_pending_i = 1'b1;
    oper_commit_i = 1'b1;
    cycle_start_i = 1'b1;
    step_clock();
    config_pending_i = 1'b0;
    oper_commit_i = 1'b0;
    cycle_start_i = 1'b0;
    check_state(8'hC3, '0, 1'b0, 1'b1,
      "empty committed list preserves initialized gate state");

    write_admin_entry(GclAddressWidth'(0),
      '{gate_states: 8'h77, interval_ticks: 32'd2});
    write_admin_length(GclLengthWidth'(1));
    @(negedge clk_i);
    config_pending_i = 1'b1;
    oper_commit_i = 1'b1;
    cycle_start_i = 1'b1;
    step_clock();
    config_pending_i = 1'b0;
    oper_commit_i = 1'b0;
    cycle_start_i = 1'b0;
    check_state(8'h77, '0, 1'b1, 1'b0, "single-entry schedule starts before reset");

    @(negedge clk_i);
    rst_ni = 1'b0;
    #1ps;
    check_state(8'hFF, '0, 1'b0, 1'b0, "asynchronous reset during execution");

    @(negedge clk_i);
    rst_ni = 1'b1;
    step_clock();
    write_admin_length(GclLengthWidth'(1));
    if (admin_write_error_o !== 1'b1 || admin_control_list_length_o !== '0) begin
      $fatal(1, "GCL entry initialization metadata was not cleared by reset");
    end

    $display("PASS: tsn_qbv_gcl_store and tsn_qbv_list_execute directed tests");
    $finish;
  end

endmodule : tsn_qbv_list_execute_tb
