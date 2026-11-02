package tsn_qbv_pkg;

  localparam int unsigned NumTrafficClasses = 8;
  localparam int unsigned GclIntervalWidth = 32;

  typedef logic [NumTrafficClasses-1:0] gate_state_t;

  // Exact integer-nanosecond arithmetic for PTP timestamps (48-bit seconds).
  typedef logic [79:0] ptp_time_ns_t;
  typedef logic [63:0] cycle_time_ns_t;

  // PTP timestamp used by the Qbv control state machines. This v1 profile
  // supports integer nanoseconds; fractional nanoseconds are not represented.
  typedef struct packed {
    logic [47:0] seconds;
    logic [31:0] nanoseconds;
  } ptp_timestamp_t;

  // Schedule timing parameters shared by Admin and Oper configuration images.
  typedef struct packed {
    ptp_timestamp_t base_time;
    cycle_time_ns_t cycle_time_ns;
    logic [31:0] cycle_time_extension_ns;
  } tsn_qbv_schedule_config_t;

  // Complete management-side image, including the independent AdminGateStates.
  typedef struct packed {
    tsn_qbv_schedule_config_t schedule;
    gate_state_t admin_gate_states;
  } tsn_qbv_admin_config_t;

  // Internal OperControlList representation consumed by List Execute.
  // TimeIntervalValue has already been normalized and converted to positive
  // implementation timebase ticks by the configuration path.
  typedef struct packed {
    gate_state_t gate_states;
    logic [GclIntervalWidth-1:0] interval_ticks;
  } oper_gcl_entry_t;

endpackage : tsn_qbv_pkg
