module tsn_qbv_apb_endpoint (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic psel_i,
  input  logic penable_i,
  input  logic pwrite_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_prot_t pprot_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t paddr_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t pwdata_i,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t pstrb_i,
  output logic pready_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t prdata_o,
  output logic pslverr_o,

  output logic request_valid_o,
  input  logic request_ready_i,
  output logic request_write_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_prot_t request_protection_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_addr_t request_address_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t request_write_data_o,
  output tsn_qbv_apb_types_pkg::tsn_qbv_apb_strb_t request_write_strobe_o,

  input  logic response_valid_i,
  output logic response_ready_o,
  input  tsn_qbv_apb_types_pkg::tsn_qbv_apb_data_t response_read_data_i,
  input  logic response_error_i
);

  import tsn_qbv_apb_types_pkg::*;

  typedef enum logic [1:0] {
    StIdle,
    StSetup,
    StRequest,
    StResponse
  } state_t;

  state_t state_q;
  logic request_write_q;
  tsn_qbv_apb_prot_t request_protection_q;
  tsn_qbv_apb_addr_t request_address_q;
  tsn_qbv_apb_data_t request_write_data_q;
  tsn_qbv_apb_strb_t request_write_strobe_q;

  logic request_accept;
  logic apb_access;

`ifndef SYNTHESIS
  logic assertions_enabled_q;
`endif

  assign apb_access = psel_i && penable_i;
  assign request_accept = request_valid_o && request_ready_i;

`ifndef SYNTHESIS
  // Keep $past-based assertions inactive during reset and through the first
  // recovery edge. This verification-only state does not affect APB logic.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      assertions_enabled_q <= 1'b0;
    end else begin
      assertions_enabled_q <= 1'b1;
    end
  end
`endif

  // APB signals are sampled in SETUP. The request channel completes when the
  // backend accepts the captured request; the response channel completes
  // separately, after the backend has produced its final read data/error.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
      request_write_q <= 1'b0;
      request_protection_q <= '0;
      request_address_q <= '0;
      request_write_data_q <= '0;
      request_write_strobe_q <= '0;
    end else begin
      case (state_q)
        StIdle: begin
          if (psel_i && !penable_i) begin
            request_write_q <= pwrite_i;
            request_protection_q <= pprot_i;
            request_address_q <= paddr_i;
            request_write_data_q <= pwdata_i;
            request_write_strobe_q <= pstrb_i;
            state_q <= StSetup;
          end
        end

        StSetup: begin
          if (!psel_i) begin
            // A transfer abandoned during SETUP has no backend side effect.
            state_q <= StIdle;
          end else if (!penable_i) begin
            // Permit an extended SETUP phase and retain its latest payload.
            request_write_q <= pwrite_i;
            request_protection_q <= pprot_i;
            request_address_q <= paddr_i;
            request_write_data_q <= pwdata_i;
            request_write_strobe_q <= pstrb_i;
          end else if (request_accept) begin
            state_q <= response_valid_i ? StIdle : StResponse;
          end else begin
            state_q <= StRequest;
          end
        end

        StRequest: begin
          if (request_accept) begin
            state_q <= response_valid_i ? StIdle : StResponse;
          end
        end

        StResponse: begin
          if (response_valid_i && response_ready_o) begin
            state_q <= StIdle;
          end
        end

        default: state_q <= StIdle;
      endcase
    end
  end

  always_comb begin
    request_valid_o = 1'b0;
    if (state_q == StRequest) begin
      request_valid_o = 1'b1;
    end else if (state_q == StSetup && apb_access) begin
      request_valid_o = 1'b1;
    end

    request_write_o = request_write_q;
    request_protection_o = request_protection_q;
    request_address_o = request_address_q;
    request_write_data_o = request_write_data_q;
    request_write_strobe_o = request_write_strobe_q;

    // A backend may return a zero-latency response together with request
    // acceptance. Otherwise it responds after request_ready_i handshakes.
    response_ready_o = apb_access &&
                       ((state_q == StResponse) || request_accept);
    pready_o = response_ready_o && response_valid_i;
    prdata_o = pready_o ? response_read_data_i : '0;
    pslverr_o = pready_o && response_error_i;
  end

`ifndef SYNTHESIS
  property p_backend_request_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      request_valid_o && !request_ready_i |=>
        request_valid_o &&
        $stable({request_write_o, request_protection_o, request_address_o,
                 request_write_data_o, request_write_strobe_o});
  endproperty

  assert property (p_backend_request_stable_while_waiting)
    else $fatal(1, "APB backend request changed before acceptance");

  property p_backend_response_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      response_valid_i && !response_ready_o |=>
        response_valid_i &&
        $stable({response_read_data_i, response_error_i});
  endproperty

  assert property (p_backend_response_stable_while_waiting)
    else $fatal(1, "APB backend response changed before acceptance");

  property p_backend_response_follows_request_acceptance;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      response_valid_i |-> (state_q == StResponse || request_accept);
  endproperty

  assert property (p_backend_response_follows_request_acceptance)
    else $fatal(1, "APB backend produced a response without an accepted request");

  property p_apb_access_stable_while_waiting;
    @(posedge clk_i) disable iff (!assertions_enabled_q)
      apb_access && !pready_o |=>
        apb_access &&
        $stable({paddr_i, pwrite_i, pprot_i, pwdata_i, pstrb_i});
  endproperty

  assert property (p_apb_access_stable_while_waiting)
    else $fatal(1, "APB master changed an ACCESS transfer before PREADY");
`endif

endmodule : tsn_qbv_apb_endpoint
