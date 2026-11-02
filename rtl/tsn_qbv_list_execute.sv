module tsn_qbv_list_execute #(
  parameter int unsigned GclDepth = 64
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic gate_enabled_i,
  input  logic cycle_start_i,  // One clk_i pulse at the scheduled cycle boundary.
  input  logic time_tick_i,    // One clk_i pulse per implementation timebase tick.
  input  tsn_qbv_pkg::gate_state_t admin_gate_states_i,

  // The owner keeps the Oper list stable while an entry is executing and
  // presents a new Oper image no later than its corresponding CycleStart.
  input  logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
             oper_control_list_length_i,
  input  tsn_qbv_pkg::oper_gcl_entry_t oper_control_list_i [GclDepth],

  output tsn_qbv_pkg::gate_state_t oper_gate_states_o,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0] list_pointer_o,
  output logic list_active_o,
  output logic list_complete_o
);

  import tsn_qbv_pkg::*;

  localparam int unsigned ListPointerWidth =
      (GclDepth > 1) ? $clog2(GclDepth + 1) : 1;
  // The pointer also represents the one-past-the-end value GclDepth, while
  // an array index must represent only [0, GclDepth-1]. Keep those widths
  // distinct so the terminal pointer can never be used as an array index.
  localparam int unsigned ListIndexWidth = (GclDepth > 1) ? $clog2(GclDepth) : 1;
  localparam logic [ListPointerWidth-1:0] ListPointerEncodingMax = '1;
  localparam bit ListLengthRangeCheckRequired =
      ListPointerEncodingMax > ListPointerWidth'(GclDepth);

  typedef enum logic [1:0] {
    StInit,
    StWaitCycleStart,
    StExecuteEntry,
    StEndOfCycle
  } state_e;

  state_e state_q, state_d;

  gate_state_t gate_states_q, gate_states_d;
  logic [ListPointerWidth-1:0] list_pointer_q, list_pointer_d;
  logic [GclIntervalWidth-1:0] interval_counter_q, interval_counter_d;
  logic [ListPointerWidth-1:0] next_list_pointer;

  // State decode and datapath next-state logic. CycleStart has priority over
  // interval expiry so a new cycle always restarts the list at entry zero.
  always_comb begin
    state_d = state_q;
    gate_states_d = gate_states_q;
    list_pointer_d = list_pointer_q;
    interval_counter_d = interval_counter_q;
    next_list_pointer = list_pointer_q + 1'b1;

    if (!gate_enabled_i) begin
      // INIT: operational gates follow the independent AdminGateStates value.
      state_d = StInit;
      gate_states_d = admin_gate_states_i;
      list_pointer_d = '0;
      interval_counter_d = '0;
    end else if (state_q == StInit) begin
      // BEGIN: initialize the executor before accepting the first cycle.
      state_d = StWaitCycleStart;
      gate_states_d = admin_gate_states_i;
      list_pointer_d = '0;
      interval_counter_d = '0;

      if (cycle_start_i) begin
        if (oper_control_list_length_i == '0) begin
          state_d = StEndOfCycle;
        end else begin
          state_d = StExecuteEntry;
          gate_states_d = oper_control_list_i[0].gate_states;
          interval_counter_d = oper_control_list_i[0].interval_ticks;
        end
      end
    end else if (cycle_start_i) begin
      // NEW_CYCLE: a cycle boundary preempts any interval still in progress.
      list_pointer_d = '0;
      interval_counter_d = '0;
      if (oper_control_list_length_i == '0) begin
        state_d = StEndOfCycle;
      end else begin
        state_d = StExecuteEntry;
        gate_states_d = oper_control_list_i[0].gate_states;
        interval_counter_d = oper_control_list_i[0].interval_ticks;
      end
    end else begin
      unique case (state_q)
        // Wait until CycleStart. INIT has already applied AdminGateStates.
        StWaitCycleStart: begin
          state_d = StWaitCycleStart;
        end

        // Execute the active entry for exactly interval_ticks timebase ticks.
        StExecuteEntry: begin
          if (time_tick_i) begin
            if (interval_counter_q == 32'd1) begin
              if (next_list_pointer < oper_control_list_length_i) begin
                list_pointer_d = next_list_pointer;
                gate_states_d =
                    oper_control_list_i[ListIndexWidth'(next_list_pointer)].gate_states;
                interval_counter_d =
                    oper_control_list_i[ListIndexWidth'(next_list_pointer)].interval_ticks;
              end else begin
                list_pointer_d = oper_control_list_length_i;
                interval_counter_d = '0;
                state_d = StEndOfCycle;
              end
            end else if (interval_counter_q > 32'd1) begin
              interval_counter_d = interval_counter_q - 1'b1;
            end else begin
              // Invalid zero-length entries are rejected by the configuration
              // path. Keep the executor out of an underflow loop if violated.
              list_pointer_d = oper_control_list_length_i;
              interval_counter_d = '0;
              state_d = StEndOfCycle;
            end
          end
        end

        // The final gate state remains active until the next CycleStart or INIT.
        StEndOfCycle: begin
          state_d = StEndOfCycle;
        end

        // Recover deterministically from an illegal state encoding.
        default: begin
          state_d = StInit;
          gate_states_d = admin_gate_states_i;
          list_pointer_d = '0;
          interval_counter_d = '0;
        end
      endcase
    end
  end

  // All registered state is updated together from the decoded next state.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StInit;
      gate_states_q <= '1;
      list_pointer_q <= '0;
      interval_counter_q <= '0;
    end else begin
      state_q <= state_d;
      gate_states_q <= gate_states_d;
      list_pointer_q <= list_pointer_d;
      interval_counter_q <= interval_counter_d;
    end
  end

  assign oper_gate_states_o = gate_states_q;
  assign list_pointer_o = list_pointer_q;
  assign list_active_o = (state_q == StExecuteEntry);
  assign list_complete_o = (state_q == StEndOfCycle);

`ifndef SYNTHESIS
  // The executor consumes only prevalidated lists. These assertions protect
  // the boundary between configuration validation and cycle execution.
  initial begin
    assert (GclDepth > 0) else $fatal(1, "GclDepth must be positive");
  end

  if (ListLengthRangeCheckRequired) begin : gen_list_length_assertion
    always_ff @(posedge clk_i) begin
      // The list-length contract is independent of reset. Avoid sampling the
      // asynchronously asserted reset in this clocked assertion process.
      assert (oper_control_list_length_i <= ListPointerWidth'(GclDepth))
        else $fatal(1, "OperControlListLength exceeds GclDepth");
    end
  end

  always_ff @(posedge clk_i) begin
    if (gate_enabled_i && cycle_start_i && oper_control_list_length_i != '0) begin
      assert (oper_control_list_i[0].interval_ticks != '0)
        else $fatal(1, "GCL entry zero has a zero interval_ticks value");
    end

    if (gate_enabled_i && state_q == StExecuteEntry && time_tick_i &&
        interval_counter_q == 32'd1 &&
        next_list_pointer < oper_control_list_length_i) begin
      assert (oper_control_list_i[ListIndexWidth'(next_list_pointer)].interval_ticks != '0)
        else $fatal(1, "GCL entry has a zero interval_ticks value");
    end

    if (gate_enabled_i && state_q == StExecuteEntry) begin
      assert (interval_counter_q != '0)
        else $fatal(1, "executor entered StExecuteEntry with an empty interval");
    end
  end
`endif

endmodule : tsn_qbv_list_execute
