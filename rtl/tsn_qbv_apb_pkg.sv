package tsn_qbv_apb_pkg;

  typedef tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t tsn_qbv_apb_addr_t;
  typedef tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t tsn_qbv_apb_data_t;

  // Register addresses are byte addresses and every register is 32-bit aligned.
  // The map intentionally exposes Admin staging registers separately from the
  // command that publishes the complete Admin image to the Qbv core.
  // Identification, runtime control, and status registers. Version/Status
  // are read-only; Status error bits are sticky until reset. Control contains
  // GateEnabled; Command is write-one-to-trigger for ConfigChange and reads zero.
  localparam tsn_qbv_apb_addr_t AddrVersion = 12'h000;
  localparam tsn_qbv_apb_addr_t AddrControl = 12'h004;
  localparam tsn_qbv_apb_addr_t AddrCommand = 12'h008;
  localparam tsn_qbv_apb_addr_t AddrStatus = 12'h00C;

  // Read/write staging image. AddrAdminConfigCommit publishes it atomically.
  localparam tsn_qbv_apb_addr_t AddrAdminBaseTimeSecondsLow = 12'h010;
  localparam tsn_qbv_apb_addr_t AddrAdminBaseTimeSecondsHigh = 12'h014;
  localparam tsn_qbv_apb_addr_t AddrAdminBaseTimeNanoseconds = 12'h018;
  localparam tsn_qbv_apb_addr_t AddrAdminCycleTimeNanosecondsLow = 12'h01C;
  localparam tsn_qbv_apb_addr_t AddrAdminCycleTimeNanosecondsHigh = 12'h020;
  localparam tsn_qbv_apb_addr_t AddrAdminCycleTimeExtensionNanoseconds = 12'h024;
  localparam tsn_qbv_apb_addr_t AddrAdminGateStates = 12'h028;
  localparam tsn_qbv_apb_addr_t AddrAdminConfigCommit = 12'h02C;

  // Read/write GCL staging registers. Entry and length commits are commands.
  localparam tsn_qbv_apb_addr_t AddrGclIndex = 12'h030;
  localparam tsn_qbv_apb_addr_t AddrGclGateStates = 12'h034;
  localparam tsn_qbv_apb_addr_t AddrGclIntervalNanoseconds = 12'h038;
  localparam tsn_qbv_apb_addr_t AddrGclEntryWrite = 12'h03C;
  localparam tsn_qbv_apb_addr_t AddrAdminGclLength = 12'h040;
  localparam tsn_qbv_apb_addr_t AddrAdminGclLengthCommit = 12'h044;

  // Read-only calculated ConfigChangeTime and ConfigChangeError.
  localparam tsn_qbv_apb_addr_t AddrConfigChangeTimeSecondsLow = 12'h048;
  localparam tsn_qbv_apb_addr_t AddrConfigChangeTimeSecondsHigh = 12'h04C;
  localparam tsn_qbv_apb_addr_t AddrConfigChangeTimeNanoseconds = 12'h050;
  localparam tsn_qbv_apb_addr_t AddrConfigChangeErrorLow = 12'h054;
  localparam tsn_qbv_apb_addr_t AddrConfigChangeErrorHigh = 12'h058;

  // Read-only Admin/Oper list and schedule state. Oper reads use one coherent
  // image captured by the write-one-to-capture OperSnapshot command.
  localparam tsn_qbv_apb_addr_t AddrAdminGclLengthStatus = 12'h05C;
  localparam tsn_qbv_apb_addr_t AddrOperBaseTimeSecondsLow = 12'h060;
  localparam tsn_qbv_apb_addr_t AddrOperBaseTimeSecondsHigh = 12'h064;
  localparam tsn_qbv_apb_addr_t AddrOperBaseTimeNanoseconds = 12'h068;
  localparam tsn_qbv_apb_addr_t AddrOperCycleTimeNanosecondsLow = 12'h06C;
  localparam tsn_qbv_apb_addr_t AddrOperCycleTimeNanosecondsHigh = 12'h070;
  localparam tsn_qbv_apb_addr_t AddrOperCycleTimeExtensionNanoseconds = 12'h074;
  localparam tsn_qbv_apb_addr_t AddrOperGclLength = 12'h078;
  localparam tsn_qbv_apb_addr_t AddrOperStatus = 12'h07C;
  localparam tsn_qbv_apb_addr_t AddrOperGateStates = 12'h080;
  localparam tsn_qbv_apb_addr_t AddrOperSnapshot = 12'h084;
  localparam tsn_qbv_apb_addr_t AddrOperSnapshotStatus = 12'h088;

  localparam tsn_qbv_apb_data_t Version = 32'h0001_0000;

  localparam int unsigned ControlGateEnabledBit = 0;
  localparam int unsigned CommandConfigChangeBit = 0;
  localparam int unsigned CommandAdminConfigCommitBit = 0;
  localparam int unsigned CommandGclEntryWriteBit = 0;
  localparam int unsigned CommandGclLengthCommitBit = 0;

  localparam int unsigned StatusAdminConfigValidBit = 0;
  localparam int unsigned StatusConfigChangeBit = 1;
  localparam int unsigned StatusConfigPendingBit = 2;
  localparam int unsigned StatusConfigChangeTimeValidBit = 3;
  localparam int unsigned StatusConfigChangeTimeOverflowBit = 4;
  localparam int unsigned StatusListActiveBit = 5;
  localparam int unsigned StatusListCompleteBit = 6;
  localparam int unsigned StatusCycleStartTimeValidBit = 7;
  localparam int unsigned StatusAdminConfigWriteErrorBit = 8;
  localparam int unsigned StatusGclWriteErrorBit = 9;

  localparam int unsigned OperStatusListActiveBit = 0;
  localparam int unsigned OperStatusListCompleteBit = 1;
  localparam int unsigned OperStatusCycleStartValidBit = 2;
  localparam int unsigned OperSnapshotCommandBit = 0;
  localparam int unsigned OperSnapshotStatusValidBit = 0;

endpackage : tsn_qbv_apb_pkg
