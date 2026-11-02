module tsn_qbv_apb_admin_stage_tb;

  import tsn_qbv_apb_types_pkg::*;
  import tsn_qbv_apb_pkg::*;
  import tsn_qbv_pkg::*;

  logic clk;
  logic rst_n;
  logic request_valid;
  logic request_ready;
  logic request_write;
  tsn_qbv_apb_addr_t request_address;
  tsn_qbv_apb_data_t request_write_data;
  tsn_qbv_apb_strb_t request_write_strobe;
  logic response_valid;
  tsn_qbv_apb_data_t response_read_data;
  logic response_error;
  tsn_qbv_admin_config_t admin_config_staging;
  logic map_checked;

  always #5 clk = ~clk;

  tsn_qbv_apb_reg_map_checker u_map_checker (
    .checked_o(map_checked)
  );

  tsn_qbv_apb_admin_stage u_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .request_valid_i(request_valid),
    .request_ready_o(request_ready),
    .request_write_i(request_write),
    .request_address_i(request_address),
    .request_write_data_i(request_write_data),
    .request_write_strobe_i(request_write_strobe),
    .response_valid_o(response_valid),
    .response_read_data_o(response_read_data),
    .response_error_o(response_error),
    .admin_config_staging_o(admin_config_staging)
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

  task automatic write_word(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t data,
    input tsn_qbv_apb_strb_t strobe,
    input logic expected_error
  );
    @(negedge clk);
    request_valid = 1'b1;
    request_write = 1'b1;
    request_address = address;
    request_write_data = data;
    request_write_strobe = strobe;
    #1;
    require(request_ready && response_valid,
            "Admin staging write must be accepted without backend wait states");
    require(response_error == expected_error,
            "Admin staging write response error mismatch");
    tick();
    request_valid = 1'b0;
    request_write = 1'b0;
    request_write_data = '0;
    request_write_strobe = '0;
    #1;
    require(!response_valid, "Admin staging response must be a single-cycle handshake");
  endtask

  task automatic read_word(
    input tsn_qbv_apb_addr_t address,
    input tsn_qbv_apb_data_t expected_data,
    input logic expected_error
  );
    @(negedge clk);
    request_valid = 1'b1;
    request_write = 1'b0;
    request_address = address;
    request_write_data = '0;
    request_write_strobe = '0;
    #1;
    require(request_ready && response_valid,
            "Admin staging read must be accepted without backend wait states");
    require(response_error == expected_error,
            "Admin staging read response error mismatch");
    require(response_read_data == expected_data,
            "Admin staging read data mismatch");
    tick();
    request_valid = 1'b0;
    #1;
    require(!response_valid, "Admin staging read response must not repeat");
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    request_valid = 1'b0;
    request_write = 1'b0;
    request_address = '0;
    request_write_data = '0;
    request_write_strobe = '0;

    repeat (2) tick();
    require(request_ready && !response_valid,
            "Zero-wait Admin staging backend must stay ready during reset");
    rst_n = 1'b1;
    tick();
    require(request_ready && !response_valid,
            "Admin staging backend must remain ready after reset release");
    require(map_checked, "APB register map contract check did not complete");

    require(admin_config_staging.schedule.base_time == '0,
            "Admin staging base time reset value mismatch");
    require(admin_config_staging.schedule.cycle_time_ns == '0,
            "Admin staging cycle time reset value mismatch");
    require(admin_config_staging.schedule.cycle_time_extension_ns == '0,
            "Admin staging cycle extension reset value mismatch");
    require(admin_config_staging.admin_gate_states == '1,
            "Admin staging gate states must reset open");

    read_word(AddrVersion, Version, 1'b0);

    write_word(AddrAdminBaseTimeSecondsLow, 32'h89AB_CDEF, 4'hF, 1'b0);
    read_word(AddrAdminBaseTimeSecondsLow, 32'h89AB_CDEF, 1'b0);
    write_word(AddrAdminBaseTimeSecondsLow, 32'h0000_1234, 4'b0101, 1'b0);
    read_word(AddrAdminBaseTimeSecondsLow, 32'h8900_CD34, 1'b0);

    write_word(AddrAdminBaseTimeSecondsHigh, 32'hDEAD_BEEF, 4'hF, 1'b0);
    read_word(AddrAdminBaseTimeSecondsHigh, 32'h0000_BEEF, 1'b0);

    // Staging deliberately does not validate the image; atomic Admin commit
    // performs schedule validation in tsn_qbv_admin_config.
    write_word(AddrAdminBaseTimeNanoseconds, 32'd1_500_000_000, 4'hF, 1'b0);
    read_word(AddrAdminBaseTimeNanoseconds, 32'd1_500_000_000, 1'b0);
    write_word(AddrAdminCycleTimeNanosecondsLow, 32'h7654_3210, 4'hF, 1'b0);
    write_word(AddrAdminCycleTimeNanosecondsHigh, 32'hFEDC_BA98, 4'hF, 1'b0);
    read_word(AddrAdminCycleTimeNanosecondsLow, 32'h7654_3210, 1'b0);
    read_word(AddrAdminCycleTimeNanosecondsHigh, 32'hFEDC_BA98, 1'b0);
    write_word(AddrAdminCycleTimeExtensionNanoseconds, 32'h1234_5678, 4'hF, 1'b0);
    read_word(AddrAdminCycleTimeExtensionNanoseconds, 32'h1234_5678, 1'b0);

    write_word(AddrAdminGateStates, 32'h0000_00A5, 4'h1, 1'b0);
    write_word(AddrAdminGateStates, 32'hFF00_0000, 4'h8, 1'b0);
    read_word(AddrAdminGateStates, 32'h0000_00A5, 1'b0);

    // A zero byte strobe is an accepted no-op, not a destructive full write.
    write_word(AddrAdminCycleTimeNanosecondsLow, 32'hFFFF_FFFF, 4'h0, 1'b0);
    read_word(AddrAdminCycleTimeNanosecondsLow, 32'h7654_3210, 1'b0);

    write_word(AddrVersion, 32'hFFFF_FFFF, 4'hF, 1'b1);
    read_word(AddrAdminConfigCommit, '0, 1'b1);
    write_word(AddrAdminConfigCommit, 32'h0000_0001, 4'hF, 1'b1);
    read_word(AddrStatus, '0, 1'b1);

    $display("PASS: TSN Qbv APB Admin staging register behavior");
    $finish;
  end

endmodule : tsn_qbv_apb_admin_stage_tb
