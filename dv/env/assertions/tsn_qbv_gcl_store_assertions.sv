`ifndef SYNTHESIS
module tsn_qbv_gcl_store_assertions (
  input logic clk_i,
  input logic rst_ni,
  input logic config_pending_i,
  input logic oper_commit_i
);

  // Avoid reading the asynchronous reset net in assertion sampling logic.
  // Reset assertion is asynchronous; assertion re-enable is clocked.
  logic assertions_enabled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
    end else begin
      assertions_enabled_q <= 1'b1;
    end
  end

  assert property (
    @(posedge clk_i) disable iff (!assertions_enabled_q)
    !oper_commit_i || config_pending_i
  ) else $fatal(1, "Oper commit requires ConfigPending");

endmodule : tsn_qbv_gcl_store_assertions
`endif
