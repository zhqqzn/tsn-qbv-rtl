module tsn_qbv_apb_admin_registers #(
  parameter int unsigned GclDepth = 64,
  parameter int unsigned TickGranularityNs = 1
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic psel_i,
  input  logic penable_i,
  input  logic pwrite_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t paddr_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t pwdata_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t pstrb_i,
  output logic pready_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t prdata_o,
  output logic pslverr_o,

  output logic admin_config_write_valid_o,
  input  logic admin_config_write_ready_i,
  output tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_write_data_o,
  input  logic admin_config_write_error_i,
  input  logic admin_config_write_done_i,
  input  logic admin_config_valid_i,
  input  logic config_change_i,
  input  logic config_pending_i,
  input  tsn_qbv_pkg::ptp_timestamp_t config_change_time_i,
  input  logic config_change_time_valid_i,
  input  logic config_change_time_overflow_i,
  input  logic [63:0] config_change_error_i,
  input  logic list_active_i,
  input  logic list_complete_i,
  input  logic cycle_start_time_valid_i,
  input  logic gcl_write_error_i,
  output logic gate_enabled_o,
  output logic config_change_set_o,
  output tsn_qbv_pkg::tsn_qbv_admin_config_t admin_config_staging_o,

  output logic admin_entry_write_valid_o,
  input  logic admin_entry_write_ready_i,
  input  logic admin_entry_write_done_i,
  input  logic admin_entry_write_error_i,
  output logic [((GclDepth > 1) ? $clog2(GclDepth) : 1)-1:0]
              admin_entry_write_address_o,
  output tsn_qbv_pkg::oper_gcl_entry_t admin_entry_write_data_o,

  output logic admin_length_write_valid_o,
  input  logic admin_length_write_ready_i,
  input  logic admin_length_write_done_i,
  input  logic admin_length_write_error_i,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              admin_length_write_data_o,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              admin_control_list_length_i,
  input  tsn_qbv_pkg::ptp_timestamp_t oper_base_time_i,
  input  tsn_qbv_pkg::cycle_time_ns_t oper_cycle_time_ns_i,
  input  logic [31:0] oper_cycle_time_extension_ns_i,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              oper_control_list_length_i,
  input  tsn_qbv_pkg::gate_state_t oper_gate_states_i
);

  import tsn_qbv_apb_types_pkg::ApbDataWidth;
  import tsn_qbv_apb_types_pkg::ApbStrobeWidth;
  import tsn_qbv_apb_types_pkg::tsn_qbv_apb_prot_t;
  import tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t;
  import tsn_qbv_apb_pkg::*;
  import tsn_qbv_pkg::*;

  localparam int unsigned GclAddressWidth =
      (GclDepth > 1) ? $clog2(GclDepth) : 1;
  localparam int unsigned GclLengthWidth =
      (GclDepth > 1) ? $clog2(GclDepth + 1) : 1;

  typedef enum logic [1:0] {
    StCommitIdle,
    StCommitSubmit,
    StCommitWaitResult,
    StCommitResponse
  } admin_commit_state_t;

  typedef enum logic [1:0] {
    StGclEntryIdle,
    StGclEntrySubmit,
    StGclEntryWaitResult,
    StGclEntryResponse
  } gcl_entry_state_t;

  typedef enum logic [1:0] {
    StGclLengthIdle,
    StGclLengthSubmit,
    StGclLengthWaitResult,
    StGclLengthResponse
  } gcl_length_state_t;

  logic request_valid;
  logic request_ready;
  logic request_write;
  tsn_qbv_apb_prot_t request_protection;
  tsn_qbv_apb_addr_t request_address;
  tsn_qbv_apb_data_t request_write_data;
  tsn_qbv_apb_strb_t request_write_strobe;
  logic response_valid;
  logic response_ready;
  tsn_qbv_apb_data_t response_read_data;
  logic response_error;

  logic is_commit_write;
  logic is_status_access;
  logic status_response_valid;
  logic status_write_error;
  logic gcl_apb_precheck_error;
  tsn_qbv_apb_data_t status_read_data;
  logic admin_config_write_error_sticky_q;
  logic gcl_write_error_sticky_q;
  logic is_control_access;
  logic is_control_write;
  logic control_write_error;
  logic control_response_valid;
  logic is_command_access;
  logic is_command_write;
  logic command_write_error;
  logic command_response_valid;
  tsn_qbv_apb_data_t command_strobed_data;
  tsn_qbv_apb_data_t command_writable_mask;
  tsn_qbv_apb_data_t control_strobed_data;
  tsn_qbv_apb_data_t control_writable_mask;
  logic gate_enabled_q;
  logic commit_command_valid;
  logic commit_invalid_response;
  logic stage_request_valid;
  logic stage_request_ready;
  logic stage_response_valid;
  tsn_qbv_apb_data_t stage_response_read_data;
  logic stage_response_error;
  logic is_gcl_stage_access;
  logic is_gcl_entry_write_access;
  logic gcl_stage_response_valid;
  tsn_qbv_apb_data_t gcl_stage_response_read_data;
  logic gcl_entry_command_valid;
  logic gcl_entry_command_format_error;
  logic gcl_entry_parameters_valid;
  logic gcl_entry_immediate_response_valid;
  logic gcl_entry_response_error_q;
  tsn_qbv_apb_data_t gcl_strobed_data;
  tsn_qbv_apb_data_t gcl_entry_command_writable_mask;
  logic [31:0] gcl_index_q;
  gate_state_t gcl_gate_states_q;
  logic [31:0] gcl_interval_nanoseconds_q;
  logic [63:0] gcl_interval_ticks_candidate;
  logic [((GclDepth > 1) ? $clog2(GclDepth) : 1)-1:0] gcl_entry_write_address_q;
  oper_gcl_entry_t gcl_entry_write_data_q;
  gcl_entry_state_t gcl_entry_state_q;
  logic is_gcl_length_stage_access;
  logic is_gcl_length_status_access;
  logic is_gcl_length_status_write_error;
  logic is_gcl_length_commit_access;
  logic is_oper_snapshot_access;
  logic oper_snapshot_response_valid;
  logic oper_snapshot_write_error;
  logic oper_snapshot_command_valid;
  logic oper_snapshot_capture;
  tsn_qbv_apb_data_t oper_snapshot_strobed_data;
  tsn_qbv_apb_data_t oper_snapshot_writable_mask;
  logic oper_snapshot_valid_q;
  ptp_timestamp_t oper_base_time_snapshot_q;
  cycle_time_ns_t oper_cycle_time_ns_snapshot_q;
  logic [31:0] oper_cycle_time_extension_ns_snapshot_q;
  logic [GclLengthWidth-1:0] oper_control_list_length_snapshot_q;
  gate_state_t oper_gate_states_snapshot_q;
  logic oper_list_active_snapshot_q;
  logic oper_list_complete_snapshot_q;
  logic oper_cycle_start_time_valid_snapshot_q;
  logic gcl_length_stage_response_valid;
  logic gcl_length_commit_command_valid;
  logic gcl_length_commit_format_error;
  logic gcl_length_commit_value_fits;
  logic gcl_length_commit_immediate_response_valid;
  logic gcl_length_commit_response_error_q;
  tsn_qbv_apb_data_t gcl_length_strobed_data;
  tsn_qbv_apb_data_t gcl_length_commit_writable_mask;
  logic [31:0] admin_gcl_length_q;
  logic [GclLengthWidth-1:0] gcl_length_write_data_q;
  gcl_length_state_t gcl_length_state_q;

  admin_commit_state_t admin_commit_state_q;
  tsn_qbv_admin_config_t admin_commit_data_q;
  logic admin_commit_response_error_q;

`ifndef SYNTHESIS
  logic assertions_enabled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
    end else begin
      assertions_enabled_q <= 1'b1;
    end
  end
`endif

  function automatic tsn_qbv_apb_data_t apply_write_strobes(
    input tsn_qbv_apb_data_t write_data,
    input tsn_qbv_apb_strb_t write_strobe
  );
    tsn_qbv_apb_data_t strobed_data;

    strobed_data = '0;
    for (int unsigned byte_index = 0; byte_index < ApbStrobeWidth; byte_index++) begin
      if (write_strobe[byte_index]) begin
        strobed_data[8*byte_index +: 8] = write_data[8*byte_index +: 8];
      end
    end
    return strobed_data;
  endfunction

  function automatic tsn_qbv_apb_data_t merge_write_strobes(
    input tsn_qbv_apb_data_t current_data,
    input tsn_qbv_apb_data_t write_data,
    input tsn_qbv_apb_strb_t write_strobe
  );
    tsn_qbv_apb_data_t merged_data;

    merged_data = current_data;
    for (int unsigned byte_index = 0; byte_index < ApbStrobeWidth; byte_index++) begin
      if (write_strobe[byte_index]) begin
        merged_data[8*byte_index +: 8] = write_data[8*byte_index +: 8];
      end
    end
    return merged_data;
  endfunction

  function automatic logic is_status_address(input tsn_qbv_apb_addr_t address);
    case (address)
      AddrStatus,
      AddrConfigChangeTimeSecondsLow,
      AddrConfigChangeTimeSecondsHigh,
      AddrConfigChangeTimeNanoseconds,
      AddrConfigChangeErrorLow,
      AddrConfigChangeErrorHigh,
      AddrOperBaseTimeSecondsLow,
      AddrOperBaseTimeSecondsHigh,
      AddrOperBaseTimeNanoseconds,
      AddrOperCycleTimeNanosecondsLow,
      AddrOperCycleTimeNanosecondsHigh,
      AddrOperCycleTimeExtensionNanoseconds,
      AddrOperGclLength,
      AddrOperStatus,
      AddrOperGateStates,
      AddrOperSnapshotStatus: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic is_gcl_stage_address(input tsn_qbv_apb_addr_t address);
    case (address)
      AddrGclIndex,
      AddrGclGateStates,
      AddrGclIntervalNanoseconds: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic is_admin_config_commit_command(
    input tsn_qbv_apb_data_t write_data,
    input tsn_qbv_apb_strb_t write_strobe
  );
    tsn_qbv_apb_data_t strobed_data;
    tsn_qbv_apb_data_t commit_bit_mask;

    strobed_data = apply_write_strobes(write_data, write_strobe);
    commit_bit_mask = '0;
    commit_bit_mask[CommandAdminConfigCommitBit] = 1'b1;

    return write_strobe[CommandAdminConfigCommitBit / 8] &&
           strobed_data[CommandAdminConfigCommitBit] &&
           ((strobed_data & ~commit_bit_mask) == '0);
  endfunction

  assign is_commit_write = request_write &&
                           (request_address == AddrAdminConfigCommit);
  assign is_status_access = is_status_address(request_address);
  assign status_response_valid = request_valid && is_status_access;
  assign status_write_error = status_response_valid && request_write;
  // Control is a local zero-wait register. Only strobed GateEnabled is writable;
  // nonzero reserved bits are rejected without changing the stored value.
  assign is_control_access = request_address == AddrControl;
  assign is_control_write = request_write && is_control_access;
  assign is_command_access = request_address == AddrCommand;
  assign is_command_write = request_write && is_command_access;
  assign is_gcl_stage_access = is_gcl_stage_address(request_address);
  assign is_gcl_entry_write_access = request_address == AddrGclEntryWrite;
  assign is_gcl_length_stage_access = request_address == AddrAdminGclLength;
  assign is_gcl_length_status_access = request_address == AddrAdminGclLengthStatus;
  assign is_gcl_length_status_write_error = request_valid &&
      is_gcl_length_status_access && request_write;
  assign is_gcl_length_commit_access = request_address == AddrAdminGclLengthCommit;
  assign is_oper_snapshot_access = request_address == AddrOperSnapshot;
  assign control_strobed_data = apply_write_strobes(
      request_write_data, request_write_strobe);
  assign control_writable_mask =
      (tsn_qbv_apb_data_t'(1) << ControlGateEnabledBit);
  assign control_write_error = request_valid && is_control_write &&
                               ((control_strobed_data & ~control_writable_mask) != '0);
  assign control_response_valid = request_valid && is_control_access;
  assign command_strobed_data = apply_write_strobes(
      request_write_data, request_write_strobe);
  assign command_writable_mask =
      (tsn_qbv_apb_data_t'(1) << CommandConfigChangeBit);
  assign command_write_error = request_valid && is_command_write &&
                               ((command_strobed_data & ~command_writable_mask) != '0);
  assign command_response_valid = request_valid && is_command_access;
  assign config_change_set_o = request_valid && request_ready && is_command_write &&
                               !command_write_error &&
                               command_strobed_data[CommandConfigChangeBit];
  assign gate_enabled_o = gate_enabled_q;
  assign commit_command_valid = is_admin_config_commit_command(
      request_write_data, request_write_strobe);
  assign commit_invalid_response = (admin_commit_state_q == StCommitIdle) &&
                                   request_valid && is_commit_write &&
                                   !commit_command_valid;
  assign gcl_strobed_data = apply_write_strobes(
      request_write_data, request_write_strobe);
  assign gcl_entry_command_writable_mask =
      (tsn_qbv_apb_data_t'(1) << CommandGclEntryWriteBit);
  assign gcl_entry_command_valid = request_write &&
      request_write_strobe[CommandGclEntryWriteBit / 8] &&
      gcl_strobed_data[CommandGclEntryWriteBit];
  assign gcl_entry_command_format_error = request_valid &&
      is_gcl_entry_write_access && request_write &&
      ((gcl_strobed_data & ~gcl_entry_command_writable_mask) != '0);
  assign gcl_interval_ticks_candidate =
      64'(gcl_interval_nanoseconds_q) /
      ((TickGranularityNs > 0) ? 64'(TickGranularityNs) : 64'd1);
  assign gcl_entry_parameters_valid = (GclDepth > 0) &&
      (TickGranularityNs > 0) &&
      (gcl_index_q < GclDepth) &&
      (gcl_interval_nanoseconds_q != 0) &&
      ((64'(gcl_interval_nanoseconds_q) %
        ((TickGranularityNs > 0) ? 64'(TickGranularityNs) : 64'd1)) == 0) &&
      (gcl_interval_ticks_candidate != 0) &&
      (gcl_interval_ticks_candidate <= 64'h0000_0000_FFFF_FFFF);
  assign gcl_entry_immediate_response_valid = request_valid &&
      is_gcl_entry_write_access &&
      (!request_write || !gcl_entry_command_valid ||
       gcl_entry_command_format_error || !gcl_entry_parameters_valid);
  assign gcl_stage_response_valid = request_valid && is_gcl_stage_access;

  assign gcl_length_strobed_data = apply_write_strobes(
      request_write_data, request_write_strobe);
  assign gcl_length_commit_writable_mask =
      (tsn_qbv_apb_data_t'(1) << CommandGclLengthCommitBit);
  assign gcl_length_commit_command_valid = request_write &&
      request_write_strobe[CommandGclLengthCommitBit / 8] &&
      gcl_length_strobed_data[CommandGclLengthCommitBit];
  assign gcl_length_commit_format_error = request_valid &&
      is_gcl_length_commit_access && request_write &&
      ((gcl_length_strobed_data & ~gcl_length_commit_writable_mask) != '0);
  // Preserve the full 32-bit staging value until this check succeeds. The
  // core owns the actual GclDepth and written-entry validation.
  assign gcl_length_commit_value_fits =
      admin_gcl_length_q == 32'(GclLengthWidth'(admin_gcl_length_q));
  assign gcl_length_commit_immediate_response_valid = request_valid &&
      is_gcl_length_commit_access &&
      (!request_write || !gcl_length_commit_command_valid ||
       gcl_length_commit_format_error ||
       (gcl_length_commit_command_valid && !gcl_length_commit_value_fits));
  assign oper_snapshot_strobed_data = apply_write_strobes(
      request_write_data, request_write_strobe);
  assign oper_snapshot_writable_mask =
      (tsn_qbv_apb_data_t'(1) << OperSnapshotCommandBit);
  assign oper_snapshot_command_valid = request_write &&
      request_write_strobe[OperSnapshotCommandBit / 8] &&
      oper_snapshot_strobed_data[OperSnapshotCommandBit];
  assign oper_snapshot_response_valid = request_valid && is_oper_snapshot_access;
  assign oper_snapshot_write_error = oper_snapshot_response_valid && request_write &&
      ((oper_snapshot_strobed_data & ~oper_snapshot_writable_mask) != '0);
  assign oper_snapshot_capture = request_valid && request_ready &&
      is_oper_snapshot_access && oper_snapshot_command_valid &&
      !oper_snapshot_write_error;
  assign gcl_apb_precheck_error = request_valid && request_ready &&
      ((is_gcl_entry_write_access && gcl_entry_immediate_response_valid &&
        (gcl_entry_command_format_error ||
         (request_write && gcl_entry_command_valid && !gcl_entry_parameters_valid))) ||
       (is_gcl_length_commit_access && gcl_length_commit_immediate_response_valid &&
        (gcl_length_commit_format_error ||
         (request_write && gcl_length_commit_command_valid &&
          !gcl_length_commit_value_fits))));
  assign gcl_length_stage_response_valid = request_valid &&
      (is_gcl_length_stage_access || is_gcl_length_status_access);

  // AdminConfigCommit is accepted into a local one-entry command state machine.
  // The complete staging image is captured at that handshake and remains
  // immutable until the core accepts it and reports explicit completion.
  assign stage_request_valid = request_valid && !is_commit_write &&
                               !is_status_access && !is_control_access &&
                               !is_command_access && !is_gcl_stage_access &&
                               !is_gcl_entry_write_access &&
                               !is_gcl_length_stage_access &&
                               !is_gcl_length_status_access &&
                               !is_gcl_length_commit_access &&
                               !is_oper_snapshot_access;
  always_comb begin
    if (is_commit_write) begin
      request_ready = admin_commit_state_q == StCommitIdle;
    end else if (is_gcl_entry_write_access) begin
      request_ready = gcl_entry_state_q == StGclEntryIdle;
    end else if (is_gcl_length_commit_access) begin
      request_ready = gcl_length_state_q == StGclLengthIdle;
    end else if (is_status_access || is_control_access || is_command_access ||
                 is_gcl_stage_access || is_gcl_length_stage_access ||
                 is_gcl_length_status_access || is_oper_snapshot_access) begin
      request_ready = 1'b1;
    end else begin
      request_ready = stage_request_ready;
    end
  end

  assign admin_config_write_valid_o = admin_commit_state_q == StCommitSubmit;
  assign admin_config_write_data_o = admin_commit_data_q;
  assign admin_entry_write_valid_o = gcl_entry_state_q == StGclEntrySubmit;
  assign admin_entry_write_address_o = gcl_entry_write_address_q;
  assign admin_entry_write_data_o = gcl_entry_write_data_q;
  assign admin_length_write_valid_o = gcl_length_state_q == StGclLengthSubmit;
  assign admin_length_write_data_o = gcl_length_write_data_q;

  assign response_valid = stage_response_valid || status_response_valid ||
                          control_response_valid || command_response_valid ||
                          commit_invalid_response ||
                          gcl_stage_response_valid || gcl_entry_immediate_response_valid ||
                          gcl_length_stage_response_valid ||
                          gcl_length_commit_immediate_response_valid ||
                          (admin_commit_state_q == StCommitResponse) ||
                          (gcl_entry_state_q == StGclEntryResponse) ||
                          (gcl_length_state_q == StGclLengthResponse) ||
                          oper_snapshot_response_valid;
  always_comb begin
    status_read_data = '0;
    status_read_data[StatusAdminConfigValidBit] = admin_config_valid_i;
    status_read_data[StatusConfigChangeBit] = config_change_i;
    status_read_data[StatusConfigPendingBit] = config_pending_i;
    status_read_data[StatusConfigChangeTimeValidBit] = config_change_time_valid_i;
    status_read_data[StatusConfigChangeTimeOverflowBit] = config_change_time_overflow_i;
    status_read_data[StatusListActiveBit] = list_active_i;
    status_read_data[StatusListCompleteBit] = list_complete_i;
    status_read_data[StatusCycleStartTimeValidBit] = cycle_start_time_valid_i;
    status_read_data[StatusAdminConfigWriteErrorBit] =
        admin_config_write_error_sticky_q;
    status_read_data[StatusGclWriteErrorBit] = gcl_write_error_sticky_q;

    if (is_status_access) begin
      case (request_address)
        AddrStatus: response_read_data = status_read_data;
        AddrConfigChangeTimeSecondsLow:
          response_read_data = config_change_time_valid_i
              ? config_change_time_i.seconds[31:0] : '0;
        AddrConfigChangeTimeSecondsHigh:
          response_read_data = config_change_time_valid_i
              ? {16'b0, config_change_time_i.seconds[47:32]} : '0;
        AddrConfigChangeTimeNanoseconds:
          response_read_data = config_change_time_valid_i
              ? config_change_time_i.nanoseconds : '0;
        AddrConfigChangeErrorLow: response_read_data = config_change_error_i[31:0];
        AddrConfigChangeErrorHigh: response_read_data = config_change_error_i[63:32];
        AddrOperBaseTimeSecondsLow:
          response_read_data = oper_base_time_snapshot_q.seconds[31:0];
        AddrOperBaseTimeSecondsHigh:
          response_read_data = {16'b0, oper_base_time_snapshot_q.seconds[47:32]};
        AddrOperBaseTimeNanoseconds:
          response_read_data = oper_base_time_snapshot_q.nanoseconds;
        AddrOperCycleTimeNanosecondsLow:
          response_read_data = oper_cycle_time_ns_snapshot_q[31:0];
        AddrOperCycleTimeNanosecondsHigh:
          response_read_data = oper_cycle_time_ns_snapshot_q[63:32];
        AddrOperCycleTimeExtensionNanoseconds:
          response_read_data = oper_cycle_time_extension_ns_snapshot_q;
        AddrOperGclLength: response_read_data = 32'(oper_control_list_length_snapshot_q);
        AddrOperStatus: begin
          response_read_data = '0;
          response_read_data[OperStatusListActiveBit] = oper_list_active_snapshot_q;
          response_read_data[OperStatusListCompleteBit] = oper_list_complete_snapshot_q;
          response_read_data[OperStatusCycleStartValidBit] = oper_cycle_start_time_valid_snapshot_q;
        end
        AddrOperGateStates: response_read_data = {24'b0, oper_gate_states_snapshot_q};
        AddrOperSnapshotStatus: begin
          response_read_data = '0;
          response_read_data[OperSnapshotStatusValidBit] = oper_snapshot_valid_q;
        end
        default: response_read_data = '0;
      endcase
    end else if (is_oper_snapshot_access) begin
      // Snapshot is write-one-to-capture and reads as zero.
      response_read_data = '0;
    end else if (is_control_access) begin
      response_read_data = {{(ApbDataWidth-1){1'b0}}, gate_enabled_q};
    end else if (is_command_access || is_gcl_entry_write_access ||
                 is_gcl_length_commit_access) begin
      // Command registers are write-one-to-trigger and read as zero.
      response_read_data = '0;
    end else if (is_gcl_length_stage_access) begin
      response_read_data = admin_gcl_length_q;
    end else if (is_gcl_length_status_access) begin
      response_read_data = 32'(admin_control_list_length_i);
    end else if (is_gcl_stage_access) begin
      response_read_data = gcl_stage_response_read_data;
    end else begin
      response_read_data = stage_response_read_data;
    end
  end
  assign response_error = stage_response_error || status_write_error ||
                          control_write_error || command_write_error ||
                          oper_snapshot_write_error ||
                          commit_invalid_response ||
                          is_gcl_length_status_write_error ||
                          (gcl_entry_immediate_response_valid &&
                           (gcl_entry_command_format_error ||
                            (request_write && gcl_entry_command_valid &&
                             !gcl_entry_parameters_valid))) ||
                          ((admin_commit_state_q == StCommitResponse) &&
                           admin_commit_response_error_q) ||
                          ((gcl_entry_state_q == StGclEntryResponse) &&
                           gcl_entry_response_error_q) ||
                          (gcl_length_commit_immediate_response_valid &&
                           (gcl_length_commit_format_error ||
                            (request_write && gcl_length_commit_command_valid &&
                             !gcl_length_commit_value_fits))) ||
                          ((gcl_length_state_q == StGclLengthResponse) &&
                           gcl_length_commit_response_error_q);

  always_comb begin
    gcl_stage_response_read_data = '0;
    case (request_address)
      AddrGclIndex: gcl_stage_response_read_data = gcl_index_q;
      AddrGclGateStates: gcl_stage_response_read_data = {24'b0, gcl_gate_states_q};
      AddrGclIntervalNanoseconds:
        gcl_stage_response_read_data = gcl_interval_nanoseconds_q;
      default: gcl_stage_response_read_data = '0;
    endcase
  end

  tsn_qbv_apb_endpoint u_endpoint (
    .clk_i,
    .rst_ni,
    .psel_i,
    .penable_i,
    .pwrite_i,
    .pprot_i(3'b000),
    .paddr_i,
    .pwdata_i,
    .pstrb_i,
    .pready_o,
    .prdata_o,
    .pslverr_o,
    .request_valid_o(request_valid),
    .request_ready_i(request_ready),
    .request_write_o(request_write),
    .request_protection_o(request_protection),
    .request_address_o(request_address),
    .request_write_data_o(request_write_data),
    .request_write_strobe_o(request_write_strobe),
    .response_valid_i(response_valid),
    .response_ready_o(response_ready),
    .response_read_data_i(response_read_data),
    .response_error_i(response_error)
  );

  tsn_qbv_apb_admin_stage u_admin_stage (
    .clk_i,
    .rst_ni,
    .request_valid_i(stage_request_valid),
    .request_ready_o(stage_request_ready),
    .request_write_i(request_write),
    .request_address_i(request_address),
    .request_write_data_i(request_write_data),
    .request_write_strobe_i(request_write_strobe),
    .response_valid_o(stage_response_valid),
    .response_read_data_o(stage_response_read_data),
    .response_error_o(stage_response_error),
    .admin_config_staging_o
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      admin_commit_state_q <= StCommitIdle;
      admin_commit_data_q <= '0;
      admin_commit_response_error_q <= 1'b0;
      admin_config_write_error_sticky_q <= 1'b0;
      gcl_write_error_sticky_q <= 1'b0;
      gate_enabled_q <= 1'b0;
      gcl_index_q <= '0;
      gcl_gate_states_q <= '0;
      gcl_interval_nanoseconds_q <= '0;
      gcl_entry_state_q <= StGclEntryIdle;
      gcl_entry_write_address_q <= '0;
      gcl_entry_write_data_q <= '0;
      gcl_entry_response_error_q <= 1'b0;
      admin_gcl_length_q <= '0;
      gcl_length_write_data_q <= '0;
      gcl_length_state_q <= StGclLengthIdle;
      gcl_length_commit_response_error_q <= 1'b0;
      oper_snapshot_valid_q <= 1'b0;
      oper_base_time_snapshot_q <= '0;
      oper_cycle_time_ns_snapshot_q <= '0;
      oper_cycle_time_extension_ns_snapshot_q <= '0;
      oper_control_list_length_snapshot_q <= '0;
      oper_gate_states_snapshot_q <= '1;
      oper_list_active_snapshot_q <= 1'b0;
      oper_list_complete_snapshot_q <= 1'b0;
      oper_cycle_start_time_valid_snapshot_q <= 1'b0;
    end else begin
      if (admin_config_write_error_i) begin
        admin_config_write_error_sticky_q <= 1'b1;
      end
      if (gcl_write_error_i || gcl_apb_precheck_error) begin
        gcl_write_error_sticky_q <= 1'b1;
      end

      if (oper_snapshot_capture) begin
        oper_base_time_snapshot_q <= oper_base_time_i;
        oper_cycle_time_ns_snapshot_q <= oper_cycle_time_ns_i;
        oper_cycle_time_extension_ns_snapshot_q <= oper_cycle_time_extension_ns_i;
        oper_control_list_length_snapshot_q <= oper_control_list_length_i;
        oper_gate_states_snapshot_q <= oper_gate_states_i;
        oper_list_active_snapshot_q <= list_active_i;
        oper_list_complete_snapshot_q <= list_complete_i;
        oper_cycle_start_time_valid_snapshot_q <= cycle_start_time_valid_i;
        oper_snapshot_valid_q <= 1'b1;
      end

      if (request_valid && request_ready && is_control_write &&
          !control_write_error &&
          request_write_strobe[ControlGateEnabledBit / 8]) begin
        gate_enabled_q <= request_write_data[ControlGateEnabledBit];
      end

      if (request_valid && request_ready && request_write && is_gcl_length_stage_access) begin
        admin_gcl_length_q <= merge_write_strobes(
            admin_gcl_length_q, request_write_data, request_write_strobe);
      end

      if (request_valid && request_ready && request_write && is_gcl_stage_access) begin
        case (request_address)
          AddrGclIndex:
            gcl_index_q <= merge_write_strobes(
                gcl_index_q, request_write_data, request_write_strobe);
          AddrGclGateStates: begin
            if (request_write_strobe[0]) begin
              gcl_gate_states_q <= request_write_data[7:0];
            end
          end
          AddrGclIntervalNanoseconds:
            gcl_interval_nanoseconds_q <= merge_write_strobes(
                gcl_interval_nanoseconds_q, request_write_data, request_write_strobe);
          default: begin
          end
        endcase
      end

      case (admin_commit_state_q)
        StCommitIdle: begin
          if (request_valid && request_ready && is_commit_write &&
              commit_command_valid) begin
            admin_commit_data_q <= admin_config_staging_o;
            admin_commit_state_q <= StCommitSubmit;
          end
        end

        StCommitSubmit: begin
          if (admin_config_write_ready_i) begin
            admin_commit_state_q <= StCommitWaitResult;
          end
        end

        StCommitWaitResult: begin
          if (admin_config_write_done_i) begin
            admin_commit_response_error_q <= admin_config_write_error_i;
            admin_commit_state_q <= StCommitResponse;
          end
        end

        StCommitResponse: begin
          if (response_ready) begin
            admin_commit_state_q <= StCommitIdle;
          end
        end

        default: admin_commit_state_q <= StCommitIdle;
      endcase

      case (gcl_entry_state_q)
        StGclEntryIdle: begin
          if (request_valid && request_ready && is_gcl_entry_write_access &&
              gcl_entry_command_valid && !gcl_entry_command_format_error &&
              gcl_entry_parameters_valid) begin
            gcl_entry_write_address_q <= GclAddressWidth'(gcl_index_q);
            gcl_entry_write_data_q <= '{
              gate_states: gcl_gate_states_q,
              interval_ticks: 32'(gcl_interval_ticks_candidate)
            };
            gcl_entry_response_error_q <= 1'b0;
            gcl_entry_state_q <= StGclEntrySubmit;
          end
        end

        StGclEntrySubmit: begin
          if (admin_entry_write_ready_i) begin
            gcl_entry_state_q <= StGclEntryWaitResult;
          end
        end

        StGclEntryWaitResult: begin
          if (admin_entry_write_done_i) begin
            gcl_entry_response_error_q <= admin_entry_write_error_i;
            gcl_entry_state_q <= StGclEntryResponse;
          end
        end

        StGclEntryResponse: begin
          if (response_ready) begin
            gcl_entry_state_q <= StGclEntryIdle;
          end
        end

        default: gcl_entry_state_q <= StGclEntryIdle;
      endcase

      case (gcl_length_state_q)
        StGclLengthIdle: begin
          if (request_valid && request_ready && is_gcl_length_commit_access &&
              gcl_length_commit_command_valid &&
              !gcl_length_commit_format_error && gcl_length_commit_value_fits) begin
            gcl_length_write_data_q <= GclLengthWidth'(admin_gcl_length_q);
            gcl_length_commit_response_error_q <= 1'b0;
            gcl_length_state_q <= StGclLengthSubmit;
          end
        end

        StGclLengthSubmit: begin
          if (admin_length_write_ready_i) begin
            gcl_length_state_q <= StGclLengthWaitResult;
          end
        end

        StGclLengthWaitResult: begin
          if (admin_length_write_done_i) begin
            gcl_length_commit_response_error_q <= admin_length_write_error_i;
            gcl_length_state_q <= StGclLengthResponse;
          end
        end

        StGclLengthResponse: begin
          if (response_ready) begin
            gcl_length_state_q <= StGclLengthIdle;
          end
        end

        default: gcl_length_state_q <= StGclLengthIdle;
      endcase
    end
  end

`ifndef SYNTHESIS
  // The wrapper omits optional PPROT pins and supplies default attributes.
  property p_gate_enabled_changes_only_on_control_write;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $changed(gate_enabled_q) |->
        $past(request_valid && request_ready && is_control_write &&
              !control_write_error &&
              request_write_strobe[ControlGateEnabledBit / 8]);
  endproperty

  assert property (p_gate_enabled_changes_only_on_control_write)
    else $fatal(1, "GateEnabled changed without an accepted Control write");

  property p_config_change_is_an_accepted_command;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      config_change_set_o |-> request_valid && request_ready &&
        is_command_write && !command_write_error &&
        command_strobed_data[CommandConfigChangeBit];
  endproperty

  assert property (p_config_change_is_an_accepted_command)
    else $fatal(1, "ConfigChange pulse was not caused by an accepted APB command");

  property p_config_change_command_is_single_cycle;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      config_change_set_o |=> !config_change_set_o;
  endproperty

  assert property (p_config_change_command_is_single_cycle)
    else $fatal(1, "ConfigChange APB command was emitted more than once");

  property p_gcl_entry_payload_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      admin_entry_write_valid_o && !admin_entry_write_ready_i |=>
        admin_entry_write_valid_o &&
        $stable({admin_entry_write_address_o, admin_entry_write_data_o});
  endproperty

  assert property (p_gcl_entry_payload_stable_while_waiting)
    else $fatal(1, "GCL entry payload changed before core acceptance");

  property p_gcl_entry_response_has_captured_result;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $rose(gcl_entry_state_q == StGclEntryResponse) |->
        $past(admin_entry_write_done_i);
  endproperty

  assert property (p_gcl_entry_response_has_captured_result)
    else $fatal(1, "GCL entry APB response was not based on core completion");

  property p_oper_snapshot_capture_is_single_cycle;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      oper_snapshot_capture |=> !oper_snapshot_capture;
  endproperty

  assert property (p_oper_snapshot_capture_is_single_cycle)
    else $fatal(1, "Oper snapshot command was captured more than once");

  property p_oper_snapshot_valid_changes_only_on_capture;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $rose(oper_snapshot_valid_q) |-> $past(oper_snapshot_capture);
  endproperty

  assert property (p_oper_snapshot_valid_changes_only_on_capture)
    else $fatal(1, "Oper snapshot became valid without an accepted command");

  property p_oper_snapshot_data_changes_only_on_capture;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $changed({
        oper_base_time_snapshot_q, oper_cycle_time_ns_snapshot_q,
        oper_cycle_time_extension_ns_snapshot_q, oper_control_list_length_snapshot_q,
        oper_gate_states_snapshot_q, oper_list_active_snapshot_q,
        oper_list_complete_snapshot_q, oper_cycle_start_time_valid_snapshot_q
      }) |-> $past(oper_snapshot_capture);
  endproperty

  assert property (p_oper_snapshot_data_changes_only_on_capture)
    else $fatal(1, "Oper snapshot changed without an accepted command");

  property p_gcl_length_payload_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      admin_length_write_valid_o && !admin_length_write_ready_i |=>
        admin_length_write_valid_o && $stable(admin_length_write_data_o);
  endproperty

  assert property (p_gcl_length_payload_stable_while_waiting)
    else $fatal(1, "Admin GCL length payload changed before core acceptance");

  property p_gcl_length_response_has_captured_result;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $rose(gcl_length_state_q == StGclLengthResponse) |->
        $past(admin_length_write_done_i);
  endproperty

  assert property (p_gcl_length_response_has_captured_result)
    else $fatal(1, "Admin GCL length APB response was not based on core completion");

  property p_default_protection_attributes;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      request_valid |-> request_protection == 3'b000;
  endproperty

  assert property (p_default_protection_attributes)
    else $fatal(1, "APB Admin register wrapper changed default PPROT attributes");

  property p_admin_commit_payload_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      admin_config_write_valid_o && !admin_config_write_ready_i |=>
        admin_config_write_valid_o && $stable(admin_config_write_data_o);
  endproperty

  assert property (p_admin_commit_payload_stable_while_waiting)
    else $fatal(1, "AdminConfigCommit payload changed before core acceptance");

  property p_admin_commit_response_has_captured_result;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      $rose(admin_commit_state_q == StCommitResponse) |->
        $past(admin_config_write_done_i);
  endproperty

  assert property (p_admin_commit_response_has_captured_result)
    else $fatal(1, "AdminConfigCommit response was not based on core completion");
`endif

endmodule : tsn_qbv_apb_admin_registers
