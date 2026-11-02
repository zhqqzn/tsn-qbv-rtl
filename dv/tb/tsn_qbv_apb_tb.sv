module tsn_qbv_apb_tb;

  import tsn_qbv_pkg::*;
  import tsn_qbv_apb_types_pkg::*;
  import tsn_qbv_apb_pkg::*;

  localparam int unsigned GclDepth = 5;
  logic clk_i;
  logic rst_ni;
  logic psel_i;
  logic penable_i;
  logic pwrite_i;
  tsn_qbv_apb_addr_t paddr_i;
  tsn_qbv_apb_data_t pwdata_i;
  tsn_qbv_apb_strb_t pstrb_i;
  logic pready_o;
  tsn_qbv_apb_data_t prdata_o;
  logic pslverr_o;
  logic reg_map_checked;

  ptp_timestamp_t current_time_i;
  logic time_tick_i;
  gate_state_t oper_gate_states_o;
  logic cycle_start_o;
  logic cycle_start_time_valid_o;
  ptp_timestamp_t cycle_start_time_o;

  tsn_qbv_apb #(
    .GclDepth(GclDepth),
    .TickGranularityNs(2)
  ) dut (.*);

  tsn_qbv_apb_reg_map_checker u_reg_map_checker (
    .checked_o(reg_map_checked)
  );

  always #5ns clk_i = ~clk_i;

  task automatic apb_write(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t data,
    input tsn_qbv_apb_strb_t strobe,
    input logic expected_error
  );
    int unsigned wait_cycles;

    @(negedge clk_i);
    psel_i = 1'b1;
    penable_i = 1'b0;
    pwrite_i = 1'b1;
    paddr_i = address;
    pwdata_i = data;
    pstrb_i = strobe;

    @(negedge clk_i);
    penable_i = 1'b1;
    wait_cycles = 0;
    // Allow combinational APB outputs to settle after driving PENABLE.
    #1ps;
    while (pready_o !== 1'b1) begin
      @(negedge clk_i);
      #1ps;
      wait_cycles++;
      if (wait_cycles > 16) begin
        $fatal(1, "APB write timed out at address 0x%03h", address);
      end
    end
    if (pslverr_o !== expected_error) begin
      $fatal(1, "APB write error mismatch at 0x%03h: got %0b expected %0b",
             address, pslverr_o, expected_error);
    end

    @(posedge clk_i);
    @(negedge clk_i);
    psel_i = 1'b0;
    penable_i = 1'b0;
    pwrite_i = 1'b0;
  endtask

  task automatic abort_admin_commit_during_reset;
    @(negedge clk_i);
    psel_i = 1'b1;
    penable_i = 1'b0;
    pwrite_i = 1'b1;
    paddr_i = AddrAdminConfigCommit;
    pwdata_i = 32'd1;
    pstrb_i = 4'b0001;

    // Capture SETUP, then hold ACCESS while ConfigPending backpressures the
    // Admin backend. The command is accepted by the endpoint exactly once,
    // but the core must not accept the Admin image yet.
    @(posedge clk_i);
    @(negedge clk_i);
    penable_i = 1'b1;
    #1ps;
    if (pready_o) begin
      $fatal(1, "APB AdminConfigCommit completed while ConfigPending was active");
    end

    @(posedge clk_i);
    #1ps;
    if (!dut.admin_config_write_valid || dut.admin_config_write_ready ||
        !dut.core_config_pending) begin
      $fatal(1, "APB AdminConfigCommit did not remain blocked by ConfigPending");
    end

    repeat (2) begin
      @(negedge clk_i);
      #1ps;
      if (pready_o || !dut.admin_config_write_valid ||
          dut.admin_config_write_ready || !dut.core_config_pending) begin
        $fatal(1, "APB wait state did not preserve the blocked Admin commit");
      end
      @(posedge clk_i);
      #1ps;
    end

    // Reset aborts the in-flight APB operation and resets both endpoint and
    // backend FSMs. The master withdraws the transfer while reset is active.
    @(negedge clk_i);
    #1ps;
    rst_ni = 1'b0;
    #1ps;
    if (pready_o || pslverr_o) begin
      $fatal(1, "APB response remained active after reset assertion");
    end
    psel_i = 1'b0;
    penable_i = 1'b0;
    pwrite_i = 1'b0;
    paddr_i = '0;
    pwdata_i = '0;
    pstrb_i = '0;

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);
    #1ps;

    if (pready_o || pslverr_o || dut.admin_config_write_valid) begin
      $fatal(1, "Reset did not cancel the pending APB transaction");
    end
  endtask

  task automatic apb_read(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t expected_data,
    input logic expected_error
  );
    int unsigned wait_cycles;

    @(negedge clk_i);
    psel_i = 1'b1;
    penable_i = 1'b0;
    pwrite_i = 1'b0;
    paddr_i = address;
    pwdata_i = '0;
    pstrb_i = '0;

    @(negedge clk_i);
    penable_i = 1'b1;
    wait_cycles = 0;
    // Allow combinational APB outputs to settle after driving PENABLE.
    #1ps;
    while (pready_o !== 1'b1) begin
      @(negedge clk_i);
      #1ps;
      wait_cycles++;
      if (wait_cycles > 16) begin
        $fatal(1, "APB read timed out at address 0x%03h", address);
      end
    end
    if (pslverr_o !== expected_error ||
        (!expected_error && prdata_o !== expected_data)) begin
      $fatal(1, "APB read mismatch at 0x%03h: data=0x%08h error=%0b",
             address, prdata_o, pslverr_o);
    end

    @(posedge clk_i);
    @(negedge clk_i);
    psel_i = 1'b0;
    penable_i = 1'b0;
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b1;
    psel_i = 1'b0;
    penable_i = 1'b0;
    pwrite_i = 1'b0;
    paddr_i = '0;
    pwdata_i = '0;
    pstrb_i = '0;
    current_time_i = '{seconds: 48'd0, nanoseconds: 32'd100};
    time_tick_i = 1'b0;

    #1ps;
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);
    #1ps;

    if (!reg_map_checked) begin
      $fatal(1, "APB register map contract was not checked");
    end

    if (oper_gate_states_o !== 8'hFF || cycle_start_o !== 1'b0 ||
        cycle_start_time_valid_o !== 1'b0 || cycle_start_time_o !== '0) begin
      $fatal(1, "APB wrapper did not propagate the functional core reset state");
    end

    apb_read(AddrVersion, Version, 1'b0);
    apb_read(AddrControl, 32'd0, 1'b0);
    apb_read(AddrAdminBaseTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrAdminBaseTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrAdminBaseTimeNanoseconds, 32'd0, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd0, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsHigh, 32'd0, 1'b0);
    apb_read(AddrAdminCycleTimeExtensionNanoseconds, 32'd0, 1'b0);
    apb_read(AddrAdminGateStates, 32'h0000_00FF, 1'b0);
    apb_read(AddrStatus, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, 32'd0, 1'b0);
    apb_read(AddrConfigChangeErrorLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeErrorHigh, 32'd0, 1'b0);
    apb_read(AddrAdminGclLengthStatus, 32'd0, 1'b0);
    apb_read(AddrOperBaseTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrOperBaseTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrOperBaseTimeNanoseconds, 32'd0, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsLow, 32'd0, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsHigh, 32'd0, 1'b0);
    apb_read(AddrOperCycleTimeExtensionNanoseconds, 32'd0, 1'b0);
    apb_read(AddrOperGclLength, 32'd0, 1'b0);
    apb_read(AddrOperStatus, 32'd0, 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_00FF, 1'b0);
    apb_read(AddrOperSnapshotStatus, 32'd0, 1'b0);

    // An integrated SETUP phase abandoned before ACCESS must not reach the
    // Admin staging bank.
    @(negedge clk_i);
    psel_i = 1'b1;
    penable_i = 1'b0;
    pwrite_i = 1'b1;
    paddr_i = AddrAdminGateStates;
    pwdata_i = 32'h0000_0011;
    pstrb_i = 4'b0001;
    @(posedge clk_i);
    #1ps;
    if (pready_o) begin
      $fatal(1, "APB SETUP phase completed without ACCESS");
    end
    @(negedge clk_i);
    psel_i = 1'b0;
    pwrite_i = 1'b0;
    paddr_i = '0;
    pwdata_i = '0;
    pstrb_i = '0;
    @(posedge clk_i);
    #1ps;
    if (pready_o) begin
      $fatal(1, "Aborted APB SETUP did not return the endpoint to idle");
    end
    apb_read(AddrAdminGateStates, 32'h0000_00FF, 1'b0);

    // Reserved Control bits are rejected and must not alter GateEnabled.
    apb_write(AddrControl, 32'h0000_0002, 4'b0001, 1'b1);
    apb_read(AddrControl, 32'd0, 1'b0);

    apb_write(AddrAdminBaseTimeSecondsLow, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrAdminBaseTimeSecondsHigh, 32'd0, 4'b0011, 1'b0);
    apb_write(AddrAdminBaseTimeNanoseconds, 32'd100, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsHigh, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeExtensionNanoseconds, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrAdminGateStates, 32'h0000_00A5, 4'b0001, 1'b0);
    apb_read(AddrAdminGateStates, 32'h0000_00A5, 1'b0);
    apb_read(AddrAdminBaseTimeNanoseconds, 32'd100, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsHigh, 32'd0, 1'b0);

    // GCL entries are staged as nanoseconds and converted to the core timebase.
    apb_write(AddrGclIndex, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrGclGateStates, 32'h0000_005A, 4'b0001, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd6, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrGclIndex, 32'd0, 1'b0);
    apb_read(AddrGclGateStates, 32'h0000_005A, 1'b0);
    apb_read(AddrGclIntervalNanoseconds, 32'd6, 1'b0);

    // GclDepth=5 exercises the non-power-of-two APB address range. The last
    // legal entry must be accepted, while the first out-of-range index fails.
    apb_write(AddrGclIndex, 32'd4, 4'b1111, 1'b0);
    apb_write(AddrGclGateStates, 32'h0000_00A4, 4'b0001, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd8, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrGclIndex, 32'd4, 1'b0);
    apb_read(AddrGclGateStates, 32'h0000_00A4, 1'b0);
    apb_read(AddrGclIntervalNanoseconds, 32'd8, 1'b0);

    apb_write(AddrGclIndex, 32'd5, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b1);

    // AdminGclLength is staged and published through a separate APB command.
    apb_write(AddrAdminGclLength, 32'd1, 4'b1111, 1'b0);
    apb_read(AddrAdminGclLength, 32'd1, 1'b0);
    apb_read(AddrAdminGclLengthStatus, 32'd0, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);
    apb_write(AddrAdminGclLengthStatus, 32'd0, 4'b1111, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);

    // Invalid APB interval is rejected before reaching the GCL store. The
    // store must consequently reject a list length that references entry one.
    apb_write(AddrGclIndex, 32'd1, 4'b1111, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd7, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrStatus, 32'(1) << StatusGclWriteErrorBit, 1'b0);
    apb_write(AddrAdminGclLength, 32'd2, 4'b1111, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd0, 4'b0001, 1'b0);
    apb_write(AddrAdminGclLength, 32'd5, 4'b1111, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);
    apb_write(AddrAdminGclLength, 32'd8, 4'b1111, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd1, 1'b0);

    // The APB command reaches the actual Qbv Admin validator through the
    // wrapper, rather than a mocked backend as in the unit-level test.
    apb_write(AddrAdminConfigCommit, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_read(AddrConfigChangeTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, 32'd100, 1'b0);
    apb_read(AddrConfigChangeErrorLow, 32'd0, 1'b0);
    apb_read(AddrConfigChangeErrorHigh, 32'd0, 1'b0);

    // An invalid new staging image must be rejected by the core validator;
    // the previously accepted Admin image must remain unchanged.
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrAdminConfigCommit, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd0, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);

    // Command is write-one-to-trigger. The request must latch in the core
    // while GateEnabled is low; reserved bits must be rejected without a side effect.
    apb_read(AddrCommand, 32'd0, 1'b0);
    // Command[0] is not written when its byte lane is not strobed.
    apb_write(AddrCommand, 32'h0000_0001, 4'b0010, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_write(AddrCommand, 32'h0000_0003, 4'b0001, 1'b1);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_write(AddrCommand, 32'h0000_0001, 4'b0001, 1'b0);
    #1ps;
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);

    // Writing zero is a no-op and must not clear the latched request.
    apb_write(AddrCommand, 32'h0000_0000, 4'b0001, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);

    apb_write(AddrControl, 32'h0000_0001, 4'b0001, 1'b0);
    @(posedge clk_i);
    #1ps;
    if (oper_gate_states_o !== 8'h5A) begin
      $fatal(1, "APB ConfigChange did not activate the APB-programmed GCL entry");
    end
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusCycleStartTimeValidBit) |
             (32'(1) << StatusListActiveBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_write(AddrOperSnapshot, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrOperSnapshotStatus,
             32'(1) << OperSnapshotStatusValidBit, 1'b0);
    apb_read(AddrOperBaseTimeSecondsLow, 32'd0, 1'b0);
    apb_read(AddrOperBaseTimeSecondsHigh, 32'd0, 1'b0);
    apb_read(AddrOperBaseTimeNanoseconds, 32'd100, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsLow, 32'd1000, 1'b0);
    apb_read(AddrOperCycleTimeNanosecondsHigh, 32'd0, 1'b0);
    apb_read(AddrOperCycleTimeExtensionNanoseconds, 32'd0, 1'b0);
    apb_read(AddrOperGclLength, 32'd1, 1'b0);
    apb_read(AddrOperStatus,
             (32'(1) << OperStatusListActiveBit) |
             (32'(1) << OperStatusCycleStartValidBit), 1'b0);
    apb_read(AddrOperGateStates, 32'h0000_005A, 1'b0);
    apb_write(AddrOperGateStates, 32'h0000_00FF, 4'b0001, 1'b1);
    apb_read(AddrOperGateStates, 32'h0000_005A, 1'b0);

    apb_read(AddrControl, 32'h0000_0001, 1'b0);
    // A write to another byte lane must preserve the GateEnabled bit.
    apb_write(AddrControl, 32'h0000_0000, 4'b0010, 1'b0);
    apb_read(AddrControl, 32'h0000_0001, 1'b0);

    // A misaligned byte address must not alias the writable Control register.
    apb_read(12'h005, 32'd0, 1'b1);
    apb_write(12'h005, 32'd0, 4'b0001, 1'b1);
    apb_read(AddrControl, 32'h0000_0001, 1'b0);

    apb_read(12'h08C, 32'd0, 1'b1);
    apb_write(12'h08C, 32'h0000_0001, 4'b0001, 1'b1);

    // Move the next ConfigChange target into the future. This creates a real
    // ConfigPending interval in the core and backpressures all Admin writes.
    apb_write(AddrAdminBaseTimeNanoseconds, 32'd200, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 4'b1111, 1'b0);
    apb_write(AddrAdminConfigCommit, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrAdminBaseTimeNanoseconds, 32'd200, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusListActiveBit) |
             (32'(1) << StatusCycleStartTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_write(AddrCommand, 32'd1, 4'b0001, 1'b0);
    #1ps;
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigPendingBit) |
             (32'(1) << StatusConfigChangeTimeValidBit) |
             (32'(1) << StatusListActiveBit) |
             (32'(1) << StatusCycleStartTimeValidBit) |
             (32'(1) << StatusAdminConfigWriteErrorBit) |
             (32'(1) << StatusGclWriteErrorBit), 1'b0);
    apb_read(AddrConfigChangeTimeNanoseconds, 32'd200, 1'b0);

    abort_admin_commit_during_reset();

    // The aborted commit must not replay after reset. A fresh APB transaction
    // must nevertheless be accepted by the reset endpoint/backend pair.
    apb_read(AddrVersion, Version, 1'b0);
    apb_read(AddrControl, 32'd0, 1'b0);
    apb_read(AddrStatus, 32'd0, 1'b0);
    apb_read(AddrOperSnapshotStatus, 32'd0, 1'b0);
    repeat (2) @(posedge clk_i);
    #1ps;
    if (dut.core_admin_config_valid || dut.admin_config_write_done) begin
      $fatal(1, "Aborted APB Admin commit was replayed after reset");
    end

    apb_write(AddrAdminBaseTimeNanoseconds, 32'd300, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 4'b1111, 1'b0);
    apb_write(AddrAdminConfigCommit, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrAdminBaseTimeNanoseconds, 32'd300, 1'b0);
    apb_read(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 1'b0);
    apb_read(AddrStatus,
             (32'(1) << StatusAdminConfigValidBit) |
             (32'(1) << StatusConfigChangeTimeValidBit), 1'b0);

    $display("PASS: tsn_qbv_apb wrapper Admin configuration integration");
    $finish;
  end

endmodule : tsn_qbv_apb_tb
