`timescale 1ns/1ps

module tsn_qbv_config_change_time_tb;

  import tsn_qbv_pkg::*;

  ptp_timestamp_t admin_base_time_i;
  cycle_time_ns_t admin_cycle_time_ns_i;
  ptp_timestamp_t current_time_i;
  ptp_timestamp_t config_change_time_o;
  logic config_change_time_valid_o;
  logic config_change_time_overflow_o;

  ptp_timestamp_t two_ns_admin_base_time_i;
  cycle_time_ns_t two_ns_admin_cycle_time_ns_i;
  ptp_timestamp_t two_ns_current_time_i;
  ptp_timestamp_t two_ns_config_change_time_o;
  logic two_ns_config_change_time_valid_o;
  logic two_ns_config_change_time_overflow_o;

  tsn_qbv_config_change_time #(
    .TickGranularityNs(1)
  ) dut (
    .admin_base_time_i,
    .admin_cycle_time_ns_i,
    .current_time_i,
    .config_change_time_o,
    .config_change_time_valid_o,
    .config_change_time_overflow_o
  );

  tsn_qbv_config_change_time #(
    .TickGranularityNs(2)
  ) dut_two_ns (
    .admin_base_time_i(two_ns_admin_base_time_i),
    .admin_cycle_time_ns_i(two_ns_admin_cycle_time_ns_i),
    .current_time_i(two_ns_current_time_i),
    .config_change_time_o(two_ns_config_change_time_o),
    .config_change_time_valid_o(two_ns_config_change_time_valid_o),
    .config_change_time_overflow_o(two_ns_config_change_time_overflow_o)
  );

  task automatic expect_two_ns_result(
    input ptp_timestamp_t admin_base_time,
    input cycle_time_ns_t admin_cycle_time_ns,
    input ptp_timestamp_t current_time,
    input logic expected_valid,
    input ptp_timestamp_t expected_time
  );
    two_ns_admin_base_time_i = admin_base_time;
    two_ns_admin_cycle_time_ns_i = admin_cycle_time_ns;
    two_ns_current_time_i = current_time;
    #1ps;

    if (two_ns_config_change_time_valid_o !== expected_valid ||
        two_ns_config_change_time_overflow_o !== 1'b0 ||
        two_ns_config_change_time_o !== expected_time) begin
      $fatal(1, "Unexpected 2-ns ConfigChangeTime result: valid=%0b overflow=%0b time=%p",
             two_ns_config_change_time_valid_o, two_ns_config_change_time_overflow_o,
             two_ns_config_change_time_o);
    end
  endtask

  task automatic expect_result(
    input ptp_timestamp_t admin_base_time,
    input cycle_time_ns_t admin_cycle_time_ns,
    input ptp_timestamp_t current_time,
    input logic expected_valid,
    input logic expected_overflow,
    input ptp_timestamp_t expected_time
  );
    admin_base_time_i = admin_base_time;
    admin_cycle_time_ns_i = admin_cycle_time_ns;
    current_time_i = current_time;
    #1ps;

    if (config_change_time_valid_o !== expected_valid ||
        config_change_time_overflow_o !== expected_overflow ||
        config_change_time_o !== expected_time) begin
      $fatal(1, "Unexpected ConfigChangeTime result: valid=%0b overflow=%0b time=%p",
             config_change_time_valid_o, config_change_time_overflow_o,
             config_change_time_o);
    end
  endtask

  initial begin
    admin_base_time_i = '0;
    admin_cycle_time_ns_i = '0;
    current_time_i = '0;
    two_ns_admin_base_time_i = '0;
    two_ns_admin_cycle_time_ns_i = '0;
    two_ns_current_time_i = '0;
    #1ps;

    // A base time in the future, or exactly now, is used without advancing it.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd200},
      64'd12,
      '{seconds: 48'd0, nanoseconds: 32'd100},
      1'b1, 1'b0,
      '{seconds: 48'd0, nanoseconds: 32'd200}
    );
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd12,
      '{seconds: 48'd0, nanoseconds: 32'd100},
      1'b1, 1'b0,
      '{seconds: 48'd0, nanoseconds: 32'd100}
    );

    // A past base time selects the first cycle boundary greater than or equal
    // to CurrentTime. An exact boundary must not be advanced by another cycle.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd10,
      '{seconds: 48'd0, nanoseconds: 32'd130},
      1'b1, 1'b0,
      '{seconds: 48'd0, nanoseconds: 32'd130}
    );
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd10,
      '{seconds: 48'd0, nanoseconds: 32'd136},
      1'b1, 1'b0,
      '{seconds: 48'd0, nanoseconds: 32'd140}
    );

    // The candidate arithmetic crosses the PTP seconds boundary.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd999_999_990},
      64'd10,
      '{seconds: 48'd1, nanoseconds: 32'd4},
      1'b1, 1'b0,
      '{seconds: 48'd1, nanoseconds: 32'd10}
    );

    // Large deltas use the full 80-bit PTP nanosecond representation.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd0},
      64'd100,
      '{seconds: 48'd10, nanoseconds: 32'd6},
      1'b1, 1'b0,
      '{seconds: 48'd10, nanoseconds: 32'd100}
    );

    // A zero period and malformed PTP nanoseconds are rejected.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd0,
      '{seconds: 48'd0, nanoseconds: 32'd120},
      1'b0, 1'b0, '0
    );
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd1_000_000_000},
      64'd10,
      '{seconds: 48'd0, nanoseconds: 32'd120},
      1'b0, 1'b0, '0
    );

    // The mathematical next boundary can exceed the representable 48-bit
    // PTP-seconds range. Do not wrap it into an earlier timestamp.
    expect_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd2,
      '{seconds: 48'hffff_ffff_ffff, nanoseconds: 32'd999_999_999},
      1'b0, 1'b1, '0
    );

    // A representable exact boundary at the end of the PTP range remains valid.
    expect_result(
      '{seconds: 48'hffff_ffff_ffff, nanoseconds: 32'd999_999_997},
      64'd2,
      '{seconds: 48'hffff_ffff_ffff, nanoseconds: 32'd999_999_999},
      1'b1, 1'b0,
      '{seconds: 48'hffff_ffff_ffff, nanoseconds: 32'd999_999_999}
    );

    // The same calculation must enforce non-unit implementation timebases.
    expect_two_ns_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd10,
      '{seconds: 48'd0, nanoseconds: 32'd104},
      1'b1,
      '{seconds: 48'd0, nanoseconds: 32'd110}
    );
    expect_two_ns_result(
      '{seconds: 48'd0, nanoseconds: 32'd100},
      64'd9,
      '{seconds: 48'd0, nanoseconds: 32'd104},
      1'b0, '0
    );
    expect_two_ns_result(
      '{seconds: 48'd0, nanoseconds: 32'd101},
      64'd10,
      '{seconds: 48'd0, nanoseconds: 32'd100},
      1'b0, '0
    );

    $display("PASS: ConfigChangeTime calculation directed tests");
    $finish;
  end

endmodule : tsn_qbv_config_change_time_tb
