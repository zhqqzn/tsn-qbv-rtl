module tsn_qbv_cycle_timer_tb;

  import tsn_qbv_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic gate_enabled_i;
  logic config_pending_i;
  ptp_timestamp_t config_change_time_i;
  logic new_config_ct_i;
  cycle_time_ns_t oper_cycle_time_ns_i;
  logic [31:0] oper_cycle_time_extension_ns_i;
  ptp_timestamp_t current_time_i;
  logic cycle_start_o;
  logic cycle_start_time_valid_o;
  ptp_timestamp_t cycle_start_time_o;
  logic new_config_ct_ack_o;

  tsn_qbv_cycle_timer #(
    .TickGranularityNs(1)
  ) dut (
    .clk_i,
    .rst_ni,
    .gate_enabled_i,
    .config_pending_i,
    .config_change_time_i,
    .new_config_ct_i,
    .oper_cycle_time_ns_i,
    .oper_cycle_time_extension_ns_i,
    .current_time_i,
    .cycle_start_o,
    .cycle_start_time_valid_o,
    .cycle_start_time_o,
    .new_config_ct_ack_o
  );

  always begin
    clk_i = 1'b0;
    #5ns;
    clk_i = 1'b1;
    #5ns;
  end

  task automatic step_clock();
    @(posedge clk_i);
    #1ps;
  endtask

  task automatic reset_timer(
    input logic [47:0] seconds,
    input logic [31:0] nanoseconds
  );
    @(negedge clk_i);
    rst_ni = 1'b0;
    gate_enabled_i = 1'b0;
    config_pending_i = 1'b0;
    config_change_time_i = '0;
    new_config_ct_i = 1'b0;
    oper_cycle_time_ns_i = '0;
    oper_cycle_time_extension_ns_i = '0;
    current_time_i = '{seconds: seconds, nanoseconds: nanoseconds};
    repeat (2) step_clock();
    @(negedge clk_i);
    rst_ni = 1'b1;
    #1ps;
  endtask

  task automatic set_time(
    input logic [47:0] seconds,
    input logic [31:0] nanoseconds
  );
    @(negedge clk_i);
    current_time_i = '{seconds: seconds, nanoseconds: nanoseconds};
    #1ps;
  endtask

  task automatic expect_cycle_start_time(
    input logic [47:0] seconds,
    input logic [31:0] nanoseconds
  );
    if (cycle_start_time_valid_o !== 1'b1 ||
        cycle_start_time_o !== '{seconds: seconds, nanoseconds: nanoseconds}) begin
      $fatal(1, "Unexpected CycleStartTime: valid=%b time=%0d.%0d",
             cycle_start_time_valid_o,
             cycle_start_time_o.seconds,
             cycle_start_time_o.nanoseconds);
    end
  endtask

  task automatic expect_no_cycle_start();
    if (cycle_start_o !== 1'b0) begin
      $fatal(1, "Unexpected CycleStart pulse");
    end
  endtask

  task automatic expect_cycle_start();
    if (cycle_start_o !== 1'b1) begin
      $fatal(1, "Expected CycleStart pulse");
    end
  endtask

  task automatic activate_schedule(
    input logic [31:0] cycle_time_ns,
    input logic [31:0] cycle_time_extension_ns
  );
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_pending_i = 1'b1;
    config_change_time_i = current_time_i;
    oper_cycle_time_ns_i = cycle_time_ns_t'(cycle_time_ns);
    oper_cycle_time_extension_ns_i = cycle_time_extension_ns;
    new_config_ct_i = 1'b1;
    #1ps;
    expect_cycle_start();
    if (new_config_ct_ack_o !== 1'b1) begin
      $fatal(1, "Initial NewConfigCT was not acknowledged");
    end
    step_clock();
    new_config_ct_i = 1'b0;
    config_pending_i = 1'b0;
    #1ps;
  endtask

  task automatic commit_pending_schedule(
    input logic [47:0] change_seconds,
    input logic [31:0] change_nanoseconds,
    input logic [31:0] cycle_time_ns,
    input logic [31:0] cycle_time_extension_ns
  );
    // List Config asserts NewConfigCT in the same cycle that CurrentTime
    // reaches ConfigChangeTime. Drive both on this negedge so the Cycle Timer
    // never samples an equality without the associated handoff request.
    @(negedge clk_i);
    current_time_i = '{seconds: change_seconds, nanoseconds: change_nanoseconds};
    oper_cycle_time_ns_i = cycle_time_ns_t'(cycle_time_ns);
    oper_cycle_time_extension_ns_i = cycle_time_extension_ns;
    new_config_ct_i = 1'b1;
    #1ps;
    if (current_time_i !== config_change_time_i) begin
      $fatal(1, "Testbench must request NewConfigCT at ConfigChangeTime");
    end
    expect_cycle_start();
    if (new_config_ct_ack_o !== 1'b1) begin
      $fatal(1, "NewConfigCT was not acknowledged at ConfigChangeTime");
    end
    step_clock();
    new_config_ct_i = 1'b0;
    config_pending_i = 1'b0;
    #1ps;
  endtask

  initial begin
    rst_ni = 1'b0;
    gate_enabled_i = 1'b0;
    config_pending_i = 1'b0;
    config_change_time_i = '0;
    new_config_ct_i = 1'b0;
    oper_cycle_time_ns_i = '0;
    oper_cycle_time_extension_ns_i = '0;
    current_time_i = '{seconds: 48'd100, nanoseconds: 32'd0};
    repeat (2) step_clock();
    @(negedge clk_i);
    rst_ni = 1'b1;

    // A first configuration starts at ConfigChangeTime. Its OperBaseTime may
    // be earlier; List Config has already calculated the legal activation time.
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_pending_i = 1'b1;
    config_change_time_i = '{seconds: 48'd100, nanoseconds: 32'd100};
    oper_cycle_time_ns_i = 64'd100;
    #1ps;
    expect_no_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd100);
    commit_pending_schedule(48'd100, 32'd100, 32'd100, 32'd0);
    expect_cycle_start_time(48'd100, 32'd200);
    expect_no_cycle_start();
    set_time(48'd100, 32'd199);
    expect_no_cycle_start();
    set_time(48'd100, 32'd200);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd300);

    // A past AdminBaseTime is represented by the future ConfigChangeTime
    // selected by List Config; Cycle Timer does not need a variable divider.
    reset_timer(48'd100, 32'd350);
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    config_pending_i = 1'b1;
    config_change_time_i = '{seconds: 48'd100, nanoseconds: 32'd400};
    oper_cycle_time_ns_i = 64'd100;
    #1ps;
    step_clock();
    expect_cycle_start_time(48'd100, 32'd400);
    commit_pending_schedule(48'd100, 32'd400, 32'd100, 32'd0);
    expect_cycle_start_time(48'd100, 32'd500);

    // A pending change does not retarget an already armed old-cycle boundary.
    // SetCycleStartTime is evaluated again only after that CycleStart.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100_000, 32'd0);
    expect_cycle_start_time(48'd100, 32'd100_000);
    @(negedge clk_i);
    config_pending_i = 1'b1;
    config_change_time_i = '{seconds: 48'd100, nanoseconds: 32'd250_000};
    oper_cycle_time_ns_i = 64'd200_000;
    #1ps;
    expect_cycle_start_time(48'd100, 32'd100_000);
    set_time(48'd100, 32'd100_000);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd200_000);
    set_time(48'd100, 32'd200_000);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd250_000);
    set_time(48'd100, 32'd249_999);
    expect_no_cycle_start();
    commit_pending_schedule(48'd100, 32'd250_000, 32'd200_000, 32'd0);
    expect_cycle_start_time(48'd100, 32'd450_000);

    // NewConfigCT can interrupt an already armed old-cycle boundary when
    // ConfigChangeTime is earlier than that boundary.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100, 32'd0);
    @(negedge clk_i);
    config_pending_i = 1'b1;
    config_change_time_i = '{seconds: 48'd100, nanoseconds: 32'd50};
    oper_cycle_time_ns_i = 64'd200;
    #1ps;
    expect_cycle_start_time(48'd100, 32'd100);
    commit_pending_schedule(48'd100, 32'd50, 32'd200, 32'd0);
    expect_cycle_start_time(48'd100, 32'd250);

    // CycleTimeExtension participates in the <= selection boundary. The old
    // 200 ns phase boundary is skipped in favor of ConfigChangeTime=250 ns.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100, 32'd50);
    @(negedge clk_i);
    config_pending_i = 1'b1;
    config_change_time_i = '{seconds: 48'd100, nanoseconds: 32'd250};
    oper_cycle_time_ns_i = 64'd200;
    #1ps;
    set_time(48'd100, 32'd100);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd250);
    set_time(48'd100, 32'd200);
    expect_no_cycle_start();
    step_clock();
    commit_pending_schedule(48'd100, 32'd250, 32'd200, 32'd0);
    expect_cycle_start_time(48'd100, 32'd450);

    // Disabling GateEnabled suppresses CycleStart but preserves an exact
    // boundary that is still current when GateEnabled is re-enabled.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100, 32'd0);
    set_time(48'd100, 32'd50);
    @(negedge clk_i);
    gate_enabled_i = 1'b0;
    #1ps;
    expect_no_cycle_start();
    set_time(48'd100, 32'd100);
    step_clock();
    if (cycle_start_time_valid_o !== 1'b0) begin
      $fatal(1, "CycleStartTime must be invalid while GateEnabled is false");
    end
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    #1ps;
    step_clock();
    expect_cycle_start_time(48'd100, 32'd100);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd200);

    // If GateEnabled is re-enabled after the boundary, the phase accumulator
    // advances to the next boundary instead of starting late at the old one.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100, 32'd0);
    set_time(48'd100, 32'd50);
    @(negedge clk_i);
    gate_enabled_i = 1'b0;
    set_time(48'd100, 32'd101);
    step_clock();
    @(negedge clk_i);
    gate_enabled_i = 1'b1;
    #1ps;
    step_clock();
    expect_cycle_start_time(48'd100, 32'd200);
    expect_no_cycle_start();

    // A late CurrentTime sample may observe a boundary one granularity step
    // after its nominal CycleStartTime; the next target must retain phase.
    reset_timer(48'd100, 32'd0);
    activate_schedule(32'd100, 32'd0);
    set_time(48'd100, 32'd101);
    expect_cycle_start();
    step_clock();
    expect_cycle_start_time(48'd100, 32'd200);

    // PTP nanoseconds roll over exactly at the seconds boundary.
    reset_timer(48'd100, 32'd999_999_900);
    activate_schedule(32'd100, 32'd0);
    expect_cycle_start_time(48'd101, 32'd0);

    // The final representable PTP boundary is valid, but advancing the phase
    // accumulator beyond it must disable the timer instead of wrapping time.
    reset_timer(48'hffff_ffff_ffff, 32'd999_999_899);
    activate_schedule(32'd100, 32'd0);
    expect_cycle_start_time(48'hffff_ffff_ffff, 32'd999_999_999);
    set_time(48'hffff_ffff_ffff, 32'd999_999_999);
    expect_cycle_start();
    step_clock();
    if (cycle_start_time_valid_o !== 1'b0 || cycle_start_time_o !== '0) begin
      $fatal(1, "Cycle Timer wrapped beyond the maximum PTP timestamp");
    end
    expect_no_cycle_start();

    $display("PASS: tsn_qbv_cycle_timer directed tests");
    $finish;
  end

endmodule : tsn_qbv_cycle_timer_tb
