module tsn_qbv_apb_admin_stage (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic request_valid_i,
  output logic request_ready_o,
  input  logic request_write_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t request_address_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t request_write_data_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t request_write_strobe_i,

  output logic response_valid_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t response_read_data_o,
  output logic response_error_o,

  output tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_staging_o
);

  import tsn_qbv_apb_types_pkg::ApbStrobeWidth;
  import tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t;
  import tsn_qbv_apb_pkg::*;
  import tsn_qbv_pkg::*;

  // This is a software shadow image. The Qbv core's live Admin image changes
  // only when a later AdminConfigCommit request is accepted and validated.
  tsn_qbv_admin_config_t admin_config_staging_q;

  function automatic tsn_qbv_apb_data_t merge_write_strobes(
    input tsn_qbv_apb_data_t current_value,
    input tsn_qbv_apb_data_t write_value,
    input tsn_qbv_apb_strb_t write_strobe
  );
    tsn_qbv_apb_data_t merged_value;

    merged_value = current_value;
    for (int unsigned byte_index = 0; byte_index < ApbStrobeWidth; byte_index++) begin
      if (write_strobe[byte_index]) begin
        merged_value[8*byte_index +: 8] = write_value[8*byte_index +: 8];
      end
    end
    return merged_value;
  endfunction

  function automatic logic [15:0] merge_write_strobes_16(
    input logic [15:0] current_value,
    input tsn_qbv_apb_data_t write_value,
    input tsn_qbv_apb_strb_t write_strobe
  );
    logic [15:0] merged_value;

    merged_value = current_value;
    for (int unsigned byte_index = 0; byte_index < 2; byte_index++) begin
      if (write_strobe[byte_index]) begin
        merged_value[8*byte_index +: 8] = write_value[8*byte_index +: 8];
      end
    end
    return merged_value;
  endfunction

  function automatic logic is_admin_stage_address(input tsn_qbv_apb_addr_t address);
    case (address)
      AddrAdminBaseTimeSecondsLow,
      AddrAdminBaseTimeSecondsHigh,
      AddrAdminBaseTimeNanoseconds,
      AddrAdminCycleTimeNanosecondsLow,
      AddrAdminCycleTimeNanosecondsHigh,
      AddrAdminCycleTimeExtensionNanoseconds,
      AddrAdminGateStates: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // This backend has no internal wait states. Its requester must keep
  // request_valid_i low while reset is asserted; tsn_qbv_apb_endpoint does so
  // by returning to StIdle. Readiness is therefore independent of rst_ni.
  assign request_ready_o = 1'b1;
  assign response_valid_o = request_valid_i;
  assign admin_config_staging_o = admin_config_staging_q;

  always_comb begin
    response_read_data_o = '0;
    response_error_o = 1'b0;

    if (request_valid_i && request_ready_o) begin
      if (request_write_i) begin
        response_error_o = !is_admin_stage_address(request_address_i);
      end else begin
        case (request_address_i)
          AddrVersion: response_read_data_o = Version;
          AddrAdminBaseTimeSecondsLow:
            response_read_data_o = admin_config_staging_q.schedule.base_time.seconds[31:0];
          AddrAdminBaseTimeSecondsHigh:
            response_read_data_o = {16'b0,
                admin_config_staging_q.schedule.base_time.seconds[47:32]};
          AddrAdminBaseTimeNanoseconds:
            response_read_data_o = admin_config_staging_q.schedule.base_time.nanoseconds;
          AddrAdminCycleTimeNanosecondsLow:
            response_read_data_o = admin_config_staging_q.schedule.cycle_time_ns[31:0];
          AddrAdminCycleTimeNanosecondsHigh:
            response_read_data_o = admin_config_staging_q.schedule.cycle_time_ns[63:32];
          AddrAdminCycleTimeExtensionNanoseconds:
            response_read_data_o =
                admin_config_staging_q.schedule.cycle_time_extension_ns;
          AddrAdminGateStates:
            response_read_data_o = {24'b0, admin_config_staging_q.admin_gate_states};
          default: response_error_o = 1'b1;
        endcase
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      admin_config_staging_q <= '{
        schedule: '{
          base_time: '{seconds: '0, nanoseconds: '0},
          cycle_time_ns: '0,
          cycle_time_extension_ns: '0
        },
        admin_gate_states: '1
      };
    end else if (request_valid_i && request_write_i &&
                 is_admin_stage_address(request_address_i)) begin
      case (request_address_i)
        AddrAdminBaseTimeSecondsLow: begin
          admin_config_staging_q.schedule.base_time.seconds[31:0] <=
              merge_write_strobes(
                  admin_config_staging_q.schedule.base_time.seconds[31:0],
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminBaseTimeSecondsHigh: begin
          // Only the low 16 bits are implemented; upper byte lanes are reserved.
          admin_config_staging_q.schedule.base_time.seconds[47:32] <=
              merge_write_strobes_16(
                  admin_config_staging_q.schedule.base_time.seconds[47:32],
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminBaseTimeNanoseconds: begin
          admin_config_staging_q.schedule.base_time.nanoseconds <=
              merge_write_strobes(
                  admin_config_staging_q.schedule.base_time.nanoseconds,
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminCycleTimeNanosecondsLow: begin
          admin_config_staging_q.schedule.cycle_time_ns[31:0] <=
              merge_write_strobes(
                  admin_config_staging_q.schedule.cycle_time_ns[31:0],
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminCycleTimeNanosecondsHigh: begin
          admin_config_staging_q.schedule.cycle_time_ns[63:32] <=
              merge_write_strobes(
                  admin_config_staging_q.schedule.cycle_time_ns[63:32],
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminCycleTimeExtensionNanoseconds: begin
          admin_config_staging_q.schedule.cycle_time_extension_ns <=
              merge_write_strobes(
                  admin_config_staging_q.schedule.cycle_time_extension_ns,
                  request_write_data_i, request_write_strobe_i);
        end
        AddrAdminGateStates: begin
          // AdminGateStates is one byte; the remaining APB lanes are reserved.
          if (request_write_strobe_i[0]) begin
            admin_config_staging_q.admin_gate_states <= request_write_data_i[7:0];
          end
        end
        default: begin
          // Unsupported and read-only writes are rejected combinationally.
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  // Keep $past-based assertions inactive during reset and through the first
  // recovery edge. This verification-only state does not affect the backend.
  logic assertions_enabled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
    end else begin
      assertions_enabled_q <= 1'b1;
    end
  end

  property p_stage_image_changes_only_on_accepted_admin_write;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $changed(admin_config_staging_q) |->
        $past(request_valid_i && request_write_i &&
              is_admin_stage_address(request_address_i));
  endproperty

  assert property (p_stage_image_changes_only_on_accepted_admin_write)
    else $fatal(1, "Admin staging image changed without an accepted write");
`endif

endmodule : tsn_qbv_apb_admin_stage
