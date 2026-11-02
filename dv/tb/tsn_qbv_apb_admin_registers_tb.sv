module tsn_qbv_apb_admin_registers_tb;

  import tsn_qbv_apb_types_pkg::*;
  import tsn_qbv_apb_pkg::*;
  import tsn_qbv_pkg::*;

  localparam ptp_timestamp_t TestCurrentTime = '{
    seconds: 48'hBEEF_8900_CD34,
    nanoseconds: 32'd100
  };

  logic clk;
  logic rst_n;
  logic psel;
  logic penable;
  logic pwrite;
  tsn_qbv_apb_addr_t paddr;
  tsn_qbv_apb_data_t pwdata;
  tsn_qbv_apb_strb_t pstrb;
  logic pready;
  tsn_qbv_apb_data_t prdata;
  logic pslverr;

  logic admin_config_write_valid;
  logic admin_config_write_ready;
  tsn_qbv_admin_config_t admin_config_write_data;
  logic admin_config_write_error;
  logic admin_config_write_done;
  logic admin_entry_write_valid;
  logic admin_entry_write_ready;
  logic admin_entry_write_done;
  logic admin_entry_write_error;
  logic [2:0] admin_entry_write_address;
  logic admin_length_write_valid;
  logic admin_length_write_ready;
  logic admin_length_write_done;
  logic admin_length_write_error;
  logic [3:0] admin_length_write_data;
  logic [3:0] admin_control_list_length;
  ptp_timestamp_t oper_base_time;
  cycle_time_ns_t oper_cycle_time_ns;
  logic [31:0] oper_cycle_time_extension_ns;
  logic [3:0] oper_control_list_length;
  gate_state_t oper_gate_states;
  logic force_gcl_length_write_error;
  int unsigned accepted_gcl_length_writes;
  oper_gcl_entry_t admin_entry_write_data;
  logic force_gcl_write_error;
  int unsigned accepted_gcl_writes;
  logic [2:0] last_gcl_write_address;
  oper_gcl_entry_t last_gcl_write_data;
  logic gate_enabled;
  logic config_change_set;
  logic config_pending;
  logic admin_config_valid;
  logic status_config_change;
  logic status_config_pending;
  logic status_config_change_time_valid;
  logic status_config_change_time_overflow;
  logic status_list_active;
  logic status_list_complete;
  logic status_cycle_start_time_valid;
  ptp_timestamp_t status_config_change_time;
  logic [63:0] status_config_change_error;
  tsn_qbv_admin_config_t admin_config;
  tsn_qbv_admin_config_t admin_config_staging;
  int unsigned accepted_admin_writes;
  int unsigned accepted_config_change_commands;
  logic map_checked;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (admin_config_write_valid && admin_config_write_ready) begin
      accepted_admin_writes <= accepted_admin_writes + 1;
    end
    if (config_change_set) begin
      accepted_config_change_commands <= accepted_config_change_commands + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      admin_entry_write_done <= 1'b0;
      admin_entry_write_error <= 1'b0;
      admin_length_write_done <= 1'b0;
      admin_length_write_error <= 1'b0;
      admin_control_list_length <= '0;
      accepted_gcl_length_writes <= 0;
      accepted_gcl_writes <= 0;
      last_gcl_write_address <= '0;
      last_gcl_write_data <= '0;
    end else begin
      admin_entry_write_done <= 1'b0;
      admin_entry_write_error <= 1'b0;
      admin_length_write_done <= 1'b0;
      admin_length_write_error <= 1'b0;
      if (admin_length_write_valid && admin_length_write_ready) begin
        admin_length_write_done <= 1'b1;
        admin_length_write_error <= force_gcl_length_write_error ||
                                    (admin_length_write_data > 4'd8);
        accepted_gcl_length_writes <= accepted_gcl_length_writes + 1;
        if (!force_gcl_length_write_error && admin_length_write_data <= 4'd8) begin
          admin_control_list_length <= admin_length_write_data;
        end
      end
      if (admin_entry_write_valid && admin_entry_write_ready) begin
        admin_entry_write_done <= 1'b1;
        admin_entry_write_error <= force_gcl_write_error;
        accepted_gcl_writes <= accepted_gcl_writes + 1;
        last_gcl_write_address <= admin_entry_write_address;
        last_gcl_write_data <= admin_entry_write_data;
      end
    end
  end

  tsn_qbv_apb_reg_map_checker u_map_checker (
    .checked_o(map_checked)
  );

  assign admin_entry_write_ready = !config_pending;
  assign admin_length_write_ready = !config_pending;

  tsn_qbv_apb_admin_registers #(
    .GclDepth(8),
    .TickGranularityNs(2)
  ) u_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .psel_i(psel),
    .penable_i(penable),
    .pwrite_i(pwrite),
    .paddr_i(paddr),
    .pwdata_i(pwdata),
    .pstrb_i(pstrb),
    .pready_o(pready),
    .prdata_o(prdata),
    .pslverr_o(pslverr),
    .admin_config_write_valid_o(admin_config_write_valid),
    .admin_config_write_ready_i(admin_config_write_ready),
    .admin_config_write_data_o(admin_config_write_data),
    .admin_config_write_error_i(admin_config_write_error),
    .admin_config_write_done_i(admin_config_write_done),
    .admin_config_valid_i(admin_config_valid),
    .config_change_i(status_config_change),
    .config_pending_i(status_config_pending),
    .config_change_time_i(status_config_change_time),
    .config_change_time_valid_i(status_config_change_time_valid),
    .config_change_time_overflow_i(status_config_change_time_overflow),
    .config_change_error_i(status_config_change_error),
    .list_active_i(status_list_active),
    .list_complete_i(status_list_complete),
    .cycle_start_time_valid_i(status_cycle_start_time_valid),
    .gcl_write_error_i(admin_entry_write_error || admin_length_write_error),
    .gate_enabled_o(gate_enabled),
    .config_change_set_o(config_change_set),
    .admin_config_staging_o(admin_config_staging),
    .admin_entry_write_valid_o(admin_entry_write_valid),
    .admin_entry_write_ready_i(admin_entry_write_ready),
    .admin_entry_write_done_i(admin_entry_write_done),
    .admin_entry_write_error_i(admin_entry_write_error),
    .admin_entry_write_address_o(admin_entry_write_address),
    .admin_entry_write_data_o(admin_entry_write_data),
    .admin_length_write_valid_o(admin_length_write_valid),
    .admin_length_write_ready_i(admin_length_write_ready),
    .admin_length_write_done_i(admin_length_write_done),
    .admin_length_write_error_i(admin_length_write_error),
    .admin_length_write_data_o(admin_length_write_data),
    .admin_control_list_length_i(admin_control_list_length),
    .oper_base_time_i(oper_base_time),
    .oper_cycle_time_ns_i(oper_cycle_time_ns),
    .oper_cycle_time_extension_ns_i(oper_cycle_time_extension_ns),
    .oper_control_list_length_i(oper_control_list_length),
    .oper_gate_states_i(oper_gate_states)
  );

  tsn_qbv_admin_config u_admin_config (
    .clk_i(clk),
    .rst_ni(rst_n),
    .config_pending_i(config_pending),
    .current_time_i(TestCurrentTime),
    .admin_config_write_valid_i(admin_config_write_valid),
    .admin_config_write_ready_o(admin_config_write_ready),
    .admin_config_write_data_i(admin_config_write_data),
    .admin_config_write_error_o(admin_config_write_error),
    .admin_config_write_done_o(admin_config_write_done),
    .admin_config_valid_o(admin_config_valid),
    .admin_config_o(admin_config)
  );

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic require(input logic condition, input string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endtask

  task automatic apb_write(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t data,
    input tsn_qbv_apb_strb_t strobe,
    input logic expected_error
  );
    bit completed;

    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    paddr = address;
    pwdata = data;
    pstrb = strobe;
    tick();

    @(negedge clk);
    penable = 1'b1;
    completed = 1'b0;
    for (int unsigned wait_cycle = 0; wait_cycle < 64; wait_cycle++) begin
      #1;
      if (pready) begin
        completed = 1'b1;
        break;
      end
      tick();
    end
    require(completed, "APB Admin write timed out waiting for PREADY");
    require(pslverr == expected_error, "APB Admin write PSLVERR mismatch");
    tick();
    require(!pready && !pslverr,
            "Completed APB Admin write must not repeat its response");
    require(!admin_config_write_done,
            "Admin config completion pulse must not remain asserted");

    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    pwdata = '0;
    pstrb = '0;
  endtask

  task automatic apb_read(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t expected_data,
    input logic expected_error
  );
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b0;
    paddr = address;
    pwdata = '0;
    pstrb = '0;
    tick();

    @(negedge clk);
    penable = 1'b1;
    #1;
    require(pready, "Zero-wait APB Admin read did not complete in ACCESS");
    require(pslverr == expected_error, "APB Admin read PSLVERR mismatch");
    require(prdata == expected_data, "APB Admin read PRDATA mismatch");
    tick();
    require(!pready && !pslverr && prdata == '0,
            "Completed APB Admin read must not repeat its response");

    psel = 1'b0;
    penable = 1'b0;
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    paddr = '0;
    pwdata = '0;
    pstrb = '0;
    config_pending = 1'b0;
    status_config_change = 1'b0;
    status_config_pending = 1'b0;
    status_config_change_time_valid = 1'b0;
    status_config_change_time_overflow = 1'b0;
    status_list_active = 1'b0;
    status_list_complete = 1'b0;
    status_cycle_start_time_valid = 1'b0;
    status_config_change_time = '0;
    status_config_change_error = 64'h0123_4567_89AB_CDEF;
    accepted_admin_writes = 0;
    accepted_config_change_commands = 0;
    force_gcl_write_error = 1'b0;
    force_gcl_length_write_error = 1'b0;
    oper_base_time = '{seconds: 48'hABCD_1234_5678, nanoseconds: 32'h8765_4321};
    oper_cycle_time_ns = 64'h1122_3344_5566_7788;
    oper_cycle_time_extension_ns = 32'hA1B2_C3D4;
    oper_control_list_length = 4'd5;
    oper_gate_states = 8'hA6;

    repeat (2) tick();
    require(!pready && !pslverr,
            "APB endpoint must remain idle during reset");
    rst_n = 1'b1;
    tick();
    require(!pready && !pslverr,
            "APB endpoint must remain idle after reset release");
    require(map_checked, "APB register map contract check did not complete");
    require(admin_config_write_ready,
            "Admin config backend should be ready when no update is pending");
    require(!gate_enabled, "GateEnabled must reset to false");

    apb_read(AddrVersion, Version, 1'b0);
    apb_read(AddrControl, 32'd0, 1'b0);
    apb_read(AddrStatus, 32'd0, 1'b0);
    apb_read(AddrOperSnapshotStatus, 32'd0, 1'b0);
    apb_read(AddrOperSnapshot, 32'd0, 1'b0);
    apb_write(AddrOperSnapshot, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrOperSnapshotStatus,
             32'(1) << OperSnapshotStatusValidBit, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, 32'd0, 1'b0);
    apb_read(AddrConfigChangeErrorLow, 32'h89AB_CDEF, 1'b0);
    apb_read(AddrConfigChangeErrorHigh, 32'h0123_4567, 1'b0);
    apb_read(AddrOperBaseTimeSecondsLow, 32'h1234_5678, 1'b0);
    apb_read(AddrOperBaseTimeSecondsHigh, 32'h0000_ABCD, 1'b0);
    apb_read(AddrOperBaseTimeNanoseconds, 32'h8765_4321, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsLow, 32'h5566_7788, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsHigh, 32'h1122_3344, 1'b0);
    apb_read(AddrOperCycleTimeExtensionNanoseconds, 32'hA1B2_C3D4, 1'b0);
    apb_read(AddrOperGclLength, 32'd5, 1'b0);
    apb_read(AddrOperStatus, 32'd0, 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_00A6, 1'b0);

    // The Oper image stays coherent after live inputs change, until a new
    // snapshot command captures the next complete image.
    oper_base_time = '{seconds: 48'h1234_5678_9ABC, nanoseconds: 32'd7654};
    oper_cycle_time_ns = 64'hAABB_CCDD_EEFF_0011;
    oper_cycle_time_extension_ns = 32'h5566_7788;
    oper_control_list_length = 4'd3;
    oper_gate_states = 8'h3C;
    status_list_active = 1'b1;
    status_list_complete = 1'b1;
    status_cycle_start_time_valid = 1'b1;
    #1;
    apb_read(AddrOperBaseTimeSecondsLow, 32'h1234_5678, 1'b0);
    apb_read(AddrOperBaseTimeSecondsHigh, 32'h0000_ABCD, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsLow, 32'h5566_7788, 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_00A6, 1'b0);
    apb_write(AddrOperSnapshot, 32'd3, 4'b0001, 1'b1);
    apb_read(AddrOperBaseTimeSecondsLow, 32'h1234_5678, 1'b0);
    apb_write(AddrOperSnapshot, 32'd1, 4'b0010, 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_00A6, 1'b0);
    apb_write(AddrOperSnapshot, 32'd0, 4'b0001, 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_00A6, 1'b0);
    apb_write(AddrOperSnapshot, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrOperBaseTimeSecondsLow, 32'h5678_9ABC, 1'b0);
    apb_read(AddrOperBaseTimeSecondsHigh, 32'h0000_1234, 1'b0);
    apb_read(AddrOperBaseTimeNanoseconds, 32'd7654, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsLow, 32'hEEFF_0011, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsHigh, 32'hAABB_CCDD, 1'b0);
    apb_read(AddrOperCycleTimeExtensionNanoseconds, 32'h5566_7788, 1'b0);
    apb_read(AddrOperGclLength, 32'd3, 1'b0);
    apb_read(AddrOperStatus,
             (32'(1) << OperStatusListActiveBit) |
             (32'(1) << OperStatusListCompleteBit) |
             (32'(1) << OperStatusCycleStartValidBit), 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_003C, 1'b0);
    apb_write(AddrOperSnapshotStatus, 32'd0, 4'hF, 1'b1);
    apb_read(AddrOperSnapshotStatus,
             32'(1) << OperSnapshotStatusValidBit, 1'b0);

    apb_read(AddrCommand, 32'd0, 1'b0);
    apb_write(AddrCommand, 32'd1, 4'b0010, 1'b0);
    require(accepted_config_change_commands == 0,
            "Unstrobed ConfigChange command caused a side effect");
    apb_write(AddrCommand, 32'd3, 4'b0001, 1'b1);
    require(accepted_config_change_commands == 0,
            "Rejected ConfigChange command caused a side effect");
    apb_write(AddrCommand, 32'd1, 4'b0001, 1'b0);
    require(accepted_config_change_commands == 1,
            "Accepted ConfigChange command was not emitted exactly once");
    apb_write(AddrCommand, 32'd0, 4'b0001, 1'b0);
    require(accepted_config_change_commands == 1,
            "No-op ConfigChange write emitted a command");
    apb_write(AddrControl, 32'h0000_0002, 4'h1, 1'b1);
    require(!gate_enabled, "Reserved Control write changed GateEnabled");
    apb_write(AddrControl, 32'h0000_0001, 4'h1, 1'b0);
    require(gate_enabled, "Control write did not update GateEnabled");
    apb_read(AddrControl, 32'h0000_0001, 1'b0);
    apb_write(AddrControl, 32'h0000_0000, 4'h2, 1'b0);
    require(gate_enabled, "Partial Control write cleared GateEnabled");
    apb_read(AddrControl, 32'h0000_0001, 1'b0);
    apb_write(AddrControl, 32'h0000_0000, 4'h1, 1'b0);
    require(!gate_enabled, "Control write did not clear GateEnabled");
    apb_read(AddrControl, 32'd0, 1'b0);

    // GCL staging accepts nanoseconds; the entry command converts them to core ticks.
    apb_write(AddrGclIndex, 32'd3, 4'hF, 1'b0);
    apb_write(AddrGclIndex, 32'h0000_0100, 4'b0010, 1'b0);
    apb_read(AddrGclIndex, 32'h0000_0103, 1'b0);
    apb_write(AddrGclIndex, 32'd3, 4'hF, 1'b0);
    apb_read(AddrGclIndex, 32'd3, 1'b0);
    apb_write(AddrGclGateStates, 32'h0000_00A5, 4'h1, 1'b0);
    apb_read(AddrGclGateStates, 32'h0000_00A5, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd10, 4'hF, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'h0000_0200, 4'b0010, 1'b0);
    apb_read(AddrGclIntervalNanoseconds, 32'h0000_020A, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd10, 4'hF, 1'b0);
    apb_read(AddrGclIntervalNanoseconds, 32'd10, 1'b0);
    config_pending = 1'b1;
    fork
      apb_write(AddrGclEntryWrite, 32'd1, 4'h1, 1'b0);
      begin
        repeat (3) tick();
        require(admin_entry_write_valid,
                "GCL entry request was not held while backend was blocked");
        require(admin_entry_write_address == 3'd3 &&
                admin_entry_write_data.gate_states == 8'hA5 &&
                admin_entry_write_data.interval_ticks == 32'd5,
                "GCL entry snapshot was not converted/captured correctly");
        config_pending = 1'b0;
      end
    join
    require(accepted_gcl_writes == 1 &&
            last_gcl_write_address == 3'd3 &&
            last_gcl_write_data == '{gate_states: 8'hA5, interval_ticks: 32'd5},
            "GCL entry command was not accepted exactly once");

    apb_write(AddrGclEntryWrite, 32'd0, 4'h1, 1'b0);
    require(accepted_gcl_writes == 1,
            "Zero GCL entry command caused a side effect");
    apb_write(AddrGclEntryWrite, 32'd1, 4'h2, 1'b0);
    require(accepted_gcl_writes == 1,
            "Unstrobed GCL entry command caused a side effect");
    apb_write(AddrGclEntryWrite, 32'd3, 4'h1, 1'b1);
    require(accepted_gcl_writes == 1,
            "Reserved GCL entry command bits caused a side effect");
    apb_write(AddrGclIntervalNanoseconds, 32'd11, 4'hF, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'h1, 1'b1);
    require(accepted_gcl_writes == 1,
            "Tick-misaligned GCL interval reached the core backend");
    apb_write(AddrGclIndex, 32'd8, 4'hF, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd10, 4'hF, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'h1, 1'b1);
    require(accepted_gcl_writes == 1,
            "Out-of-range GCL index reached the core backend");
    apb_write(AddrGclIndex, 32'd2, 4'hF, 1'b0);
    force_gcl_write_error = 1'b1;
    apb_write(AddrGclEntryWrite, 32'd1, 4'h1, 1'b1);
    force_gcl_write_error = 1'b0;
    require(accepted_gcl_writes == 2,
            "Backend-rejected GCL entry was not accepted exactly once");

    // AdminGclLength is staged independently and published by a one-shot command.
    apb_write(AddrAdminGclLength, 32'd1, 4'hF, 1'b0);
    apb_read(AddrAdminGclLength, 32'd1, 1'b0);
    apb_read(AddrAdminGclLengthStatus, 32'd0, 1'b0);
    apb_write(AddrAdminGclLengthStatus, 32'd7, 4'hF, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd0, 1'b0);
    config_pending = 1'b1;
    fork
      apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h1, 1'b0);
      begin
        repeat (3) tick();
        require(admin_length_write_valid,
                "Admin GCL length request was not held while backend was blocked");
        require(admin_length_write_data == 4'd1,
                "Admin GCL length snapshot changed while waiting");
        config_pending = 1'b0;
      end
    join
    require(accepted_gcl_length_writes == 1 && admin_control_list_length == 4'd1,
            "Admin GCL length commit was not accepted exactly once");
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);
    apb_write(AddrAdminGclLength, 32'hAB00_0000, 4'b1000, 1'b0);
    apb_read(AddrAdminGclLength, 32'hAB00_0001, 1'b0);
    apb_write(AddrAdminGclLength, 32'd0, 4'b1000, 1'b0);
    apb_read(AddrAdminGclLength, 32'd1, 1'b0);

    // The empty Admin list is a valid publication, and can be replaced later.
    apb_write(AddrAdminGclLength, 32'd0, 4'hF, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h1, 1'b0);
    require(accepted_gcl_length_writes == 2 && admin_control_list_length == 4'd0,
            "Empty Admin GCL list was not committed");
    apb_read(AddrAdminGclLengthStatus, 32'd0, 1'b0);
    apb_write(AddrAdminGclLength, 32'd1, 4'hF, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h1, 1'b0);
    require(accepted_gcl_length_writes == 3 && admin_control_list_length == 4'd1,
            "Admin GCL list length could not be restored after empty publication");

    apb_write(AddrAdminGclLengthCommit, 32'd0, 4'h1, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h2, 1'b0);
    require(accepted_gcl_length_writes == 3,
            "No-op or unstrobed Admin GCL length command caused a side effect");
    apb_write(AddrAdminGclLengthCommit, 32'd3, 4'h1, 1'b1);
    require(accepted_gcl_length_writes == 3,
            "Reserved Admin GCL length command bits caused a side effect");
    apb_write(AddrAdminGclLength, 32'd16, 4'hF, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h1, 1'b1);
    require(accepted_gcl_length_writes == 3,
            "Oversized Admin GCL length reached the narrow core interface");
    apb_write(AddrAdminGclLength, 32'd9, 4'hF, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'h1, 1'b1);
    require(accepted_gcl_length_writes == 4 && admin_control_list_length == 4'd1,
            "Core-rejected Admin GCL length modified the published length");
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);

    apb_write(AddrAdminBaseTimeSecondsLow, 32'h89AB_CDEF, 4'hF, 1'b0);
    apb_read(AddrAdminBaseTimeSecondsLow, 32'h89AB_CDEF, 1'b0);
    apb_write(AddrAdminBaseTimeSecondsLow, 32'h0000_1234, 4'b0101, 1'b0);
    apb_read(AddrAdminBaseTimeSecondsLow, 32'h8900_CD34, 1'b0);

    apb_write(AddrAdminBaseTimeSecondsHigh, 32'hDEAD_BEEF, 4'hF, 1'b0);
    apb_read(AddrAdminBaseTimeSecondsHigh, 32'h0000_BEEF, 1'b0);
    apb_write(AddrAdminBaseTimeNanoseconds, 32'd100, 4'hF, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 4'hF, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsHigh, 32'd0, 4'hF, 1'b0);
    apb_write(AddrAdminCycleTimeExtensionNanoseconds, 32'd0, 4'hF, 1'b0);
    apb_write(AddrAdminGateStates, 32'h0000_00A5, 4'h1, 1'b0);

    apb_read(AddrAdminBaseTimeNanoseconds, 32'd100, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsHigh, 32'd0, 1'b0);
    apb_read(AddrAdminCycleTimeExtensionNanoseconds, 32'd0, 1'b0);
    apb_read(AddrAdminGateStates, 32'h0000_00A5, 1'b0);

    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'hFFFF_FFFF, 4'h0, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 1'b0);
    apb_write(AddrVersion, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_read(AddrAdminConfigCommit, '0, 1'b1);
    apb_write(AddrAdminConfigCommit, 32'd0, 4'h1, 1'b1);

    // ConfigPending backpressures the core interface. The APB request is
    // accepted once, its snapshot remains held, and ACCESS completes only
    // after the core is allowed to accept and validate the image.
    config_pending = 1'b1;
    fork
      apb_write(AddrAdminConfigCommit, 32'd1, 4'h1, 1'b0);
      begin
        repeat (4) tick();
        config_pending = 1'b0;
      end
    join

    require(accepted_admin_writes == 1,
            "AdminConfigCommit must be accepted exactly once");
    require(admin_config_valid && admin_config == admin_config_staging,
            "Valid AdminConfigCommit did not publish the staging image");

    // The staging bank deliberately accepts raw field values. The core
    // validates the complete image and reports the rejection via PSLVERR.
    apb_write(AddrAdminBaseTimeNanoseconds, 32'd1_000_000_000, 4'hF, 1'b0);
    apb_write(AddrAdminConfigCommit, 32'd1, 4'h1, 1'b1);
    require(accepted_admin_writes == 2,
            "Rejected AdminConfigCommit was duplicated or not accepted");
    require(admin_config_valid &&
            admin_config.schedule.base_time.nanoseconds == 32'd100,
            "Rejected AdminConfigCommit changed the previous Admin image");

    require(admin_config_staging.schedule.base_time.seconds == 48'hBEEF_8900_CD34,
            "Integrated Admin staging seconds image mismatch");
    require(admin_config_staging.admin_gate_states == 8'hA5,
            "Integrated Admin staging gate state mismatch");

    // The Status flags are live core state, while error indications are
    // sticky until reset so software can read them after the failed command.
    status_config_change = 1'b1;
    status_config_pending = 1'b1;
    status_config_change_time_valid = 1'b1;
    status_config_change_time_overflow = 1'b0;
    status_list_active = 1'b1;
    status_list_complete = 1'b1;
    status_cycle_start_time_valid = 1'b1;
    status_config_change_time = TestCurrentTime;
    #1;
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeBit) |
             (32'(1) << StatusConfigPendingBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusListActiveBit) |
             (32'(1) << StatusListCompleteBit) |
             (32'(1) << StatusCycleStartTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_read(AddrConfigChangeTimeSecondsLow, TestCurrentTime.seconds[31:0], 1'b0);
    apb_read(AddrConfigChangeTimeSecondsHigh,
             {16'b0, TestCurrentTime.seconds[47:32]}, 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, TestCurrentTime.nanoseconds, 1'b0);
    apb_read(AddrConfigChangeErrorLow, 32'h89AB_CDEF, 1'b0);
    apb_read(AddrConfigChangeErrorHigh, 32'h0123_4567, 1'b0);
    apb_write(AddrOperSnapshot, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrOperStatus,
             (32'(1) << OperStatusListActiveBit) |
             (32'(1) << OperStatusListCompleteBit) |
             (32'(1) << OperStatusCycleStartValidBit), 1'b0);

    status_config_change_time_valid = 1'b0;
    status_config_change_time_overflow = 1'b1;
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeBit) |
             (32'(1) << StatusConfigPendingBit) |
             (32'(1) << StatusConfigChangeTimeOverflowBit) |
             (32'(1) << StatusListActiveBit) |
             (32'(1) << StatusListCompleteBit) |
             (32'(1) << StatusCycleStartTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_read(AddrConfigChangeTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, 32'd0, 1'b0);

    apb_write(AddrStatus, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_write(AddrConfigChangeTimeSecondsLow, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_write(AddrConfigChangeErrorHigh, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_write(AddrOperBaseTimeSecondsLow, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_write(AddrOperGateStates, 32'hFFFF_FFFF, 4'hF, 1'b1);
    apb_write(AddrOperSnapshotStatus, 32'hFFFF_FFFF, 4'hF, 1'b1);

    $display("PASS: TSN Qbv APB Admin register integration and commit");
    $finish;
  end

endmodule : tsn_qbv_apb_admin_registers_tb
