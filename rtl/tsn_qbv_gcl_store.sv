module tsn_qbv_gcl_store #(
  parameter int unsigned GclDepth = 64
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic config_pending_i,
  input  logic oper_commit_i,

  input  logic admin_entry_write_valid_i,
  output logic admin_write_ready_o,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth) : 1)-1:0]
             admin_entry_write_address_i,
  input  tsn_qbv_pkg::oper_gcl_entry_t admin_entry_write_data_i,

  input  logic admin_length_write_valid_i,
  input  logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
             admin_length_write_data_i,
  output logic admin_write_error_o,
  output logic admin_entry_write_done_o,
  output logic admin_entry_write_error_o,
  output logic admin_length_write_done_o,
  output logic admin_length_write_error_o,

  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              admin_control_list_length_o,
  output logic [((GclDepth > 1) ? $clog2(GclDepth + 1) : 1)-1:0]
              oper_control_list_length_o,
  output wire tsn_qbv_pkg::oper_gcl_entry_t oper_control_list_o [GclDepth]
);

  localparam int unsigned GclAddressWidth =
      (GclDepth > 1) ? $clog2(GclDepth) : 1;
  localparam int unsigned GclLengthWidth =
      (GclDepth > 1) ? $clog2(GclDepth + 1) : 1;
  localparam int unsigned GclAddressCompareWidth = GclAddressWidth + 1;
  localparam logic [GclLengthWidth-1:0] GclLengthEncodingMax = '1;
  localparam bit GclLengthRangeCheckRequired =
      GclLengthEncodingMax > GclLengthWidth'(GclDepth);

  import tsn_qbv_pkg::*;

  oper_gcl_entry_t admin_control_list_q [GclDepth];
  oper_gcl_entry_t oper_control_list_q [GclDepth];
  logic [GclLengthWidth-1:0] admin_control_list_length_q;
  logic [GclLengthWidth-1:0] oper_control_list_length_q;
  logic admin_write_error_q;
  logic admin_entry_write_done_q;
  logic admin_entry_write_error_q;
  logic admin_length_write_done_q;
  logic admin_length_write_error_q;
  logic [GclDepth-1:0] admin_entry_valid_q, admin_entry_valid_d;
  logic admin_length_entries_valid;
  logic admin_length_in_range;
  logic oper_commit_accept;

  // The commit bypass makes the new Oper image visible to List Execute before
  // the active clock edge. Thus CycleStart and Admin-to-Oper activation can be
  // sampled on the same edge without executing entry zero from the old image.
  // The management write interface is inactive during reset. Do not expose
  // a ready handshake or a commit bypass until the storage state is live.
  assign admin_write_ready_o = rst_ni && !config_pending_i;
  assign oper_commit_accept = rst_ni && oper_commit_i && config_pending_i;
  assign admin_write_error_o = admin_write_error_q;
  assign admin_entry_write_done_o = admin_entry_write_done_q;
  assign admin_entry_write_error_o = admin_entry_write_error_q;
  assign admin_length_write_done_o = admin_length_write_done_q;
  assign admin_length_write_error_o = admin_length_write_error_q;
  assign admin_control_list_length_o = admin_control_list_length_q;
  assign oper_control_list_length_o =
      oper_commit_accept ? admin_control_list_length_q : oper_control_list_length_q;

  // Skip the range comparator when every representable length is legal.
  // This is the case when every encoded value is within the depth.
  generate
    if (GclLengthRangeCheckRequired) begin : gen_length_range_check
      assign admin_length_in_range =
          admin_length_write_data_i <= GclLengthWidth'(GclDepth);
    end else begin : gen_length_always_in_range
      assign admin_length_in_range = 1'b1;
    end
  endgenerate

  // Track valid entries separately so the GCL array remains eligible for RAM
  // inference without a reset requirement. A published list may reference
  // only entries written since reset with a nonzero normalized interval.
  always_comb begin
    admin_entry_valid_d = admin_entry_valid_q;
    if (admin_entry_write_valid_i && admin_write_ready_o &&
        (GclAddressCompareWidth'(admin_entry_write_address_i) <
         GclAddressCompareWidth'(GclDepth)) &&
        (admin_entry_write_data_i.interval_ticks != '0)) begin
      admin_entry_valid_d[admin_entry_write_address_i] = 1'b1;
    end

    admin_length_entries_valid = 1'b1;
    for (int unsigned index = 0; index < GclDepth; index++) begin
      if ((GclLengthWidth'(index) < admin_length_write_data_i) &&
          !admin_entry_valid_d[index]) begin
        admin_length_entries_valid = 1'b0;
      end
    end
  end

  for (genvar index = 0; index < GclDepth; index++) begin : gen_oper_list_output
    assign oper_control_list_o[index] = oper_commit_accept
                                             ? admin_control_list_q[index]
                                             : oper_control_list_q[index];
  end

  // GCL contents are intentionally not reset. A zero length makes every entry
  // unreachable until software writes it and publishes a valid list length.
  // The bounded v1 implementation uses register arrays; storage packing and
  // memory inference remain private to this module's consumer boundary.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      admin_control_list_length_q <= '0;
      oper_control_list_length_q <= '0;
      admin_write_error_q <= 1'b0;
      admin_entry_write_done_q <= 1'b0;
      admin_entry_write_error_q <= 1'b0;
      admin_length_write_done_q <= 1'b0;
      admin_length_write_error_q <= 1'b0;
      admin_entry_valid_q <= '0;
    end else begin
      admin_write_error_q <= 1'b0;
      admin_entry_write_done_q <= admin_entry_write_valid_i && admin_write_ready_o;
      admin_entry_write_error_q <= 1'b0;
      admin_length_write_done_q <= admin_length_write_valid_i && admin_write_ready_o;
      admin_length_write_error_q <= 1'b0;
      admin_entry_valid_q <= admin_entry_valid_d;

      if (admin_entry_write_valid_i && admin_write_ready_o) begin
        if (GclAddressCompareWidth'(admin_entry_write_address_i) <
            GclAddressCompareWidth'(GclDepth)) begin
          if (admin_entry_write_data_i.interval_ticks != '0) begin
            admin_control_list_q[admin_entry_write_address_i] <= admin_entry_write_data_i;
          end else begin
            admin_write_error_q <= 1'b1;
            admin_entry_write_error_q <= 1'b1;
          end
        end else begin
          admin_write_error_q <= 1'b1;
          admin_entry_write_error_q <= 1'b1;
        end
      end

      if (admin_length_write_valid_i && admin_write_ready_o) begin
        if (admin_length_in_range && admin_length_entries_valid) begin
          admin_control_list_length_q <= admin_length_write_data_i;
        end else begin
          admin_write_error_q <= 1'b1;
          admin_length_write_error_q <= 1'b1;
        end
      end

      if (oper_commit_accept) begin
        for (int unsigned index = 0; index < GclDepth; index++) begin
          oper_control_list_q[index] <= admin_control_list_q[index];
        end
        oper_control_list_length_q <= admin_control_list_length_q;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (GclDepth > 0) else $fatal(1, "GclDepth must be positive");
  end
`endif

endmodule : tsn_qbv_gcl_store
