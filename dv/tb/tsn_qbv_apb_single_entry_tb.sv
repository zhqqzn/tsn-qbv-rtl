module tsn_qbv_apb_single_entry_tb;

  import tsn_qbv_pkg::*;
  import tsn_qbv_apb_types_pkg::*;
  import tsn_qbv_apb_pkg::*;

  localparam int unsigned GclDepth = 1;

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

  ptp_timestamp_t current_time_i;
  logic time_tick_i;
  gate_state_t oper_gate_states_o;
  logic cycle_start_o;
  logic cycle_start_time_valid_o;
  ptp_timestamp_t cycle_start_time_o;

  tsn_qbv_apb #(
    .GclDepth(GclDepth),
    .TickGranularityNs(1)
  ) dut (.*);

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

  task automatic apb_read(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t expected_data
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
    #1ps;
    while (pready_o !== 1'b1) begin
      @(negedge clk_i);
      #1ps;
      wait_cycles++;
      if (wait_cycles > 16) begin
        $fatal(1, "APB read timed out at address 0x%03h", address);
      end
    end
    if (pslverr_o !== 1'b0 || prdata_o !== expected_data) begin
      $fatal(1, "APB read mismatch at 0x%03h: data=0x%08h expected=0x%08h error=%0b",
             address, prdata_o, expected_data, pslverr_o);
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

    // GclDepth=1 uses one bit for both the entry index and list length.
    // The full-width APB staging registers must reject values before narrowing.
    apb_write(AddrGclIndex, 32'd1, 4'b1111, 1'b0);
    apb_write(AddrGclGateStates, 32'h0000_00A4, 4'b0001, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd10, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b1);

    apb_write(AddrGclIndex, 32'd0, 4'b1111, 1'b0);
    apb_write(AddrGclGateStates, 32'h0000_00A5, 4'b0001, 1'b0);
    apb_write(AddrGclIntervalNanoseconds, 32'd10, 4'b1111, 1'b0);
    apb_write(AddrGclEntryWrite, 32'd1, 4'b0001, 1'b0);

    apb_write(AddrAdminGclLength, 32'd2, 4'b1111, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b1);
    apb_read(AddrAdminGclLengthStatus, 32'd0);
    apb_write(AddrAdminGclLength, 32'd1, 4'b1111, 1'b0);
    apb_write(AddrAdminGclLengthCommit, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrAdminGclLengthStatus, 32'd1);

    apb_write(AddrAdminBaseTimeNanoseconds, 32'd100, 4'b1111, 1'b0);
    apb_write(AddrAdminCycleTimeNanosecondsLow, 32'd1000, 4'b1111, 1'b0);
    apb_write(AddrAdminConfigCommit, 32'd1, 4'b0001, 1'b0);
    apb_write(AddrCommand, 32'd1, 4'b0001, 1'b0);
    apb_write(AddrControl, 32'd1, 4'b0001, 1'b0);

    @(posedge clk_i);
    #1ps;
    if (oper_gate_states_o !== 8'hA5 || cycle_start_o !== 1'b0 ||
        cycle_start_time_valid_o !== 1'b1 || cycle_start_time_o === '0) begin
      $fatal(1, "Single-entry GCL did not commit and arm its next cycle");
    end

    apb_write(AddrOperSnapshot, 32'd1, 4'b0001, 1'b0);
    apb_read(AddrOperGclLength, 32'd1);
    apb_read(AddrOperGateStates, 32'h0000_00A5);

    $display("PASS: tsn_qbv_apb single-entry GCL parameter test");
    $finish;
  end

endmodule : tsn_qbv_apb_single_entry_tb
