// SPDX-License-Identifier: Apache-2.0

module tb;

  timeunit 1ns;
  timeprecision 1ps;

  import uvm_pkg::*;
  import tsn_qbv_pkg::*;
  import tsn_qbv_apb_types_pkg::*;
  import tsn_qbv_env_pkg::*;
  import tsn_qbv_test_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  logic clk_i;
  logic rst_ni;
  ptp_timestamp_t current_time_i;
  logic time_tick_i;
  gate_state_t oper_gate_states_o;
  logic cycle_start_o;
  logic cycle_start_time_valid_o;
  ptp_timestamp_t cycle_start_time_o;

  always #(CLK_PERIOD / 2) clk_i = ~clk_i;

  apb_if #(
    .ADDR_WIDTH(ApbAddressWidth),
    .DATA_WIDTH(ApbDataWidth)
  ) apb_vif (
    .PCLK(clk_i),
    .PRESETn(rst_ni)
  );

  wire dut_pready;
  wire [ApbDataWidth-1:0] dut_prdata;
  wire dut_pslverr;

  tsn_qbv_apb dut (
    .clk_i,
    .rst_ni,
    .psel_i(apb_vif.PSELx),
    .penable_i(apb_vif.PENABLE),
    .pwrite_i(apb_vif.PWRITE),
    .paddr_i(apb_vif.PADDR),
    .pwdata_i(apb_vif.PWDATA),
    .pstrb_i(apb_vif.PSTRB),
    .pready_o(dut_pready),
    .prdata_o(dut_prdata),
    .pslverr_o(dut_pslverr),
    .current_time_i,
    .time_tick_i,
    .oper_gate_states_o,
    .cycle_start_o,
    .cycle_start_time_valid_o,
    .cycle_start_time_o
  );

  // DUT response ports terminate on nets first. The reusable APB interface
  // also exposes these signals as slave_cb output clockvars for completer-agent
  // topologies. IEEE 1800-2023 14.16.2 prohibits continuous assignments to
  // variables associated with output clockvars, but permits procedural
  // assignments. This environment uses the APB master agent only, so bridge
  // the DUT response into the shared bus procedurally.
  always @* begin
    apb_vif.PREADY = dut_pready;
    apb_vif.PRDATA = dut_prdata;
    apb_vif.PSLVERR = dut_pslverr;
  end

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    current_time_i = '0;
    time_tick_i = 1'b0;
    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
  end

  initial begin : check_reset_outputs
    wait (rst_ni === 1'b1);
    @(negedge clk_i);
    if (oper_gate_states_o !== '1 ||
        cycle_start_o !== 1'b0 ||
        cycle_start_time_valid_o !== 1'b0 ||
        cycle_start_time_o !== '0) begin
      $fatal(1, "TSN Qbv functional outputs do not match their reset state");
    end
  end

  initial begin
    uvm_config_db #(
      virtual apb_if #(
        .ADDR_WIDTH(ApbAddressWidth),
        .DATA_WIDTH(ApbDataWidth)
      )
    )::set(
      null, "uvm_test_top.*", "vif", apb_vif);
    run_test();
  end

endmodule : tb
