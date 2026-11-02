module tsn_qbv_apb_reg_map_checker (
  output logic checked_o
);

  import tsn_qbv_apb_pkg::*;

  localparam int unsigned RegisterCount = 35;
  localparam tsn_qbv_apb_addr_t RegisterAddresses[RegisterCount] = '{
    AddrVersion,
    AddrControl,
    AddrCommand,
    AddrStatus,
    AddrAdminBaseTimeSecondsLow,
    AddrAdminBaseTimeSecondsHigh,
    AddrAdminBaseTimeNanoseconds,
    AddrAdminCycleTimeNanosecondsLow,
    AddrAdminCycleTimeNanosecondsHigh,
    AddrAdminCycleTimeExtensionNanoseconds,
    AddrAdminGateStates,
    AddrAdminConfigCommit,
    AddrGclIndex,
    AddrGclGateStates,
    AddrGclIntervalNanoseconds,
    AddrGclEntryWrite,
    AddrAdminGclLength,
    AddrAdminGclLengthCommit,
    AddrConfigChangeTimeSecondsLow,
    AddrConfigChangeTimeSecondsHigh,
    AddrConfigChangeTimeNanoseconds,
    AddrConfigChangeErrorLow,
    AddrConfigChangeErrorHigh,
    AddrAdminGclLengthStatus,
    AddrOperBaseTimeSecondsLow,
    AddrOperBaseTimeSecondsHigh,
    AddrOperBaseTimeNanoseconds,
    AddrOperCycleTimeNanosecondsLow,
    AddrOperCycleTimeNanosecondsHigh,
    AddrOperCycleTimeExtensionNanoseconds,
    AddrOperGclLength,
    AddrOperStatus,
    AddrOperGateStates,
    AddrOperSnapshot,
    AddrOperSnapshotStatus
  };

  localparam int unsigned RegisterBitCount = 20;
  localparam int unsigned RegisterBitIndices[RegisterBitCount] = '{
    ControlGateEnabledBit,
    CommandConfigChangeBit,
    CommandAdminConfigCommitBit,
    CommandGclEntryWriteBit,
    CommandGclLengthCommitBit,
    StatusAdminConfigValidBit,
    StatusConfigChangeBit,
    StatusConfigPendingBit,
    StatusConfigChangeTimeValidBit,
    StatusConfigChangeTimeOverflowBit,
    StatusListActiveBit,
    StatusListCompleteBit,
    StatusCycleStartTimeValidBit,
    StatusAdminConfigWriteErrorBit,
    StatusGclWriteErrorBit,
    OperStatusListActiveBit,
    OperStatusListCompleteBit,
    OperStatusCycleStartValidBit,
    OperSnapshotCommandBit,
    OperSnapshotStatusValidBit
  };

  initial begin
    checked_o = 1'b0;
    for (int unsigned index = 0; index < RegisterCount; index++) begin
      if (RegisterAddresses[index][1:0] != 2'b00) begin
        $fatal(1, "APB register address is not word aligned: %03h",
               RegisterAddresses[index]);
      end
      if (32'(RegisterAddresses[index]) >= (32'd1 << tsn_qbv_apb_types_pkg::ApbAddressWidth)) begin
        $fatal(1, "APB register address exceeds PADDR width: %03h",
               RegisterAddresses[index]);
      end
      for (int unsigned other = index + 1; other < RegisterCount; other++) begin
        if (RegisterAddresses[index] == RegisterAddresses[other]) begin
          $fatal(1, "Duplicate APB register address: %03h", RegisterAddresses[index]);
        end
      end
    end

    if (AddrOperSnapshotStatus != 12'h088 || Version != 32'h0001_0000) begin
      $fatal(1, "APB register map boundary or version changed unexpectedly");
    end

    if (tsn_qbv_apb_types_pkg::ApbDataWidth != 32 ||
        tsn_qbv_apb_types_pkg::ApbAddressWidth != 12) begin
      $fatal(1, "Unsupported APB register interface width");
    end

    for (int unsigned index = 0; index < RegisterBitCount; index++) begin
      if (RegisterBitIndices[index] >= tsn_qbv_apb_types_pkg::ApbDataWidth) begin
        $fatal(1, "APB register bit index exceeds data width: %0d",
               RegisterBitIndices[index]);
      end
    end
    checked_o = 1'b1;
  end

endmodule : tsn_qbv_apb_reg_map_checker
