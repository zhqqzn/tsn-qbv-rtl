module tsn_qbv_apb_endpoint_tb;

  import tsn_qbv_apb_types_pkg::*;

  logic clk;
  logic rst_n;
  logic psel;
  logic penable;
  logic pwrite;
  tsn_qbv_apb_prot_t pprot;
  tsn_qbv_apb_addr_t paddr;
  tsn_qbv_apb_data_t pwdata;
  tsn_qbv_apb_strb_t pstrb;
  logic pready;
  tsn_qbv_apb_data_t prdata;
  logic pslverr;

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
  int unsigned accepted_request_count;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accepted_request_count <= 0;
    end else if (request_valid && request_ready) begin
      accepted_request_count <= accepted_request_count + 1;
    end
  end

  tsn_qbv_apb_endpoint u_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .psel_i(psel),
    .penable_i(penable),
    .pwrite_i(pwrite),
    .pprot_i(pprot),
    .paddr_i(paddr),
    .pwdata_i(pwdata),
    .pstrb_i(pstrb),
    .pready_o(pready),
    .prdata_o(prdata),
    .pslverr_o(pslverr),
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

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic require(input logic condition, input string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    pprot = '0;
    paddr = '0;
    pwdata = '0;
    pstrb = '0;
    request_ready = 1'b0;
    response_valid = 1'b0;
    response_read_data = '0;
    response_error = 1'b0;

    repeat (2) tick();
    rst_n = 1'b1;
    tick();
    require(!request_valid && !response_ready && !pready,
            "Reset must leave the endpoint idle");
    require(!pslverr && prdata == '0,
            "Response outputs must be inactive while idle");

    // Setup payload is captured and is not issued until ACCESS begins.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    pprot = 3'b101;
    paddr = 12'h034;
    pwdata = 32'h0000_00A5;
    pstrb = 4'b0011;
    tick();
    require(!request_valid && !response_ready && !pready,
            "SETUP must not launch a backend request");

    // Request acceptance can stall independently from response generation.
    @(negedge clk);
    penable = 1'b1;
    response_read_data = 32'hDEAD_BEEF;
    response_error = 1'b1;
    #1;
    require(request_valid && !response_ready && !pready,
            "First ACCESS cycle must present a request, not a response");
    require(request_write && request_protection == 3'b101 &&
            request_address == 12'h034,
            "Captured write direction/protection/address mismatch");
    require(request_write_data == 32'h0000_00A5 && request_write_strobe == 4'b0011,
            "Captured write payload mismatch");

    repeat (3) begin
      tick();
      require(request_valid && !response_ready && !pready,
              "Unaccepted request must remain asserted during backend wait");
      require(!pslverr && prdata == '0,
              "Response fields must remain invalid before response acceptance");
      require(request_address == 12'h034 && request_write_data == 32'h0000_00A5,
              "Backend request must remain stable before acceptance");
    end

    request_ready = 1'b1;
    response_valid = 1'b0;
    #1;
    require(request_valid && request_ready,
            "Backend must accept the held request exactly at the handshake");
    require(response_ready && !pready,
            "Response channel must be ready after request acceptance");
    tick();
    require(!request_valid && response_ready && !pready,
            "Accepted request must not be reissued while response is pending");

    repeat (2) begin
      tick();
      require(!request_valid && response_ready && !pready,
              "Response wait must not repeat the backend request");
    end

    response_valid = 1'b1;
    #1;
    require(response_ready && pready && pslverr,
            "APB must complete with the backend error response");
    require(prdata == 32'hDEAD_BEEF,
            "APB read data must match the completed backend response");
    tick();
    require(!request_valid && !response_ready && !pready && !pslverr,
            "A completed access must not be issued a second time");
    response_valid = 1'b0;
    require(accepted_request_count == 1,
            "The first APB transfer must be accepted exactly once");

    // A SETUP phase abandoned before ACCESS must have no side effect.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    pprot = 3'b000;
    paddr = 12'h03C;
    pwdata = 32'h0000_0001;
    pstrb = 4'hF;
    request_ready = 1'b0;
    response_valid = 1'b0;
    tick();
    @(negedge clk);
    psel = 1'b0;
    penable = 1'b0;
    tick();
    require(!request_valid && !response_ready && !pready,
            "Aborted SETUP must not reach the backend");
    require(accepted_request_count == 1,
            "Aborted SETUP must not be counted as an accepted request");

    // A zero-latency backend may accept a request and return its response
    // during the first ACCESS cycle.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b0;
    pprot = 3'b000;
    paddr = 12'h000;
    pwdata = '0;
    pstrb = '0;
    request_ready = 1'b1;
    response_valid = 1'b0;
    response_read_data = 32'h0001_0000;
    response_error = 1'b0;
    tick();
    @(negedge clk);
    penable = 1'b1;
    #1;
    require(request_valid && response_ready && !pready,
            "Zero-wait request must be presented before its response");
    response_valid = 1'b1;
    #1;
    require(request_valid && response_ready && pready,
            "Zero-latency read must complete in first ACCESS cycle");
    require(!request_write && request_address == 12'h000,
            "Read request direction/address mismatch");
    require(prdata == 32'h0001_0000 && !pslverr,
            "Zero-latency read response mismatch");
    tick();
    require(!request_valid && !response_ready && !pready,
            "Zero-latency read must complete exactly once");
    response_valid = 1'b0;
    require(accepted_request_count == 2,
            "Both APB transfers must be accepted exactly once");

    // APB permits back-to-back transfers without deasserting PSEL. The
    // completed ACCESS is followed by SETUP for the next request.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    pprot = 3'b010;
    paddr = 12'h040;
    pwdata = 32'h1234_5678;
    pstrb = 4'b1100;
    request_ready = 1'b1;
    response_valid = 1'b0;
    response_read_data = '0;
    response_error = 1'b0;
    tick();
    require(!request_valid && !response_ready && !pready,
            "Back-to-back SETUP must not launch a backend request");

    @(negedge clk);
    penable = 1'b1;
    #1;
    require(request_valid && request_write && request_address == 12'h040 &&
            request_write_data == 32'h1234_5678 && request_write_strobe == 4'b1100 &&
            request_protection == 3'b010,
            "Back-to-back ACCESS payload mismatch");
    response_valid = 1'b1;
    response_read_data = 32'hCAFE_BABE;
    #1;
    require(response_ready && pready && !pslverr && prdata == 32'hCAFE_BABE,
            "Back-to-back APB response mismatch");
    tick();
    require(!request_valid && !response_ready && !pready && !pslverr,
            "Back-to-back transfer must complete exactly once");
    response_valid = 1'b0;
    require(accepted_request_count == 3,
            "Back-to-back transfer must be accepted exactly once");

    // Reset must cancel a request that the backend has not accepted. The
    // APB master returns the bus to IDLE while PRESETn is asserted.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    pprot = 3'b000;
    paddr = 12'h048;
    pwdata = 32'hDEAD_BEEF;
    pstrb = 4'hF;
    request_ready = 1'b0;
    response_valid = 1'b0;
    tick();
    @(negedge clk);
    penable = 1'b1;
    #1;
    require(request_valid && !request_ready && !pready,
            "Stalled ACCESS must retain an unaccepted backend request");
    tick();
    require(request_valid && !request_ready,
            "Unaccepted request must remain pending before reset");

    @(negedge clk);
    rst_n = 1'b0;
    psel = 1'b0;
    penable = 1'b0;
    #1;
    require(!request_valid && !response_ready && !pready && !pslverr &&
            prdata == '0,
            "Reset must cancel a pending unaccepted backend request");
    repeat (2) tick();
    rst_n = 1'b1;
    tick();
    require(!request_valid && !response_ready && !pready && !pslverr,
            "Endpoint must remain idle after reset releases a stalled request");

    // Reset must also cancel a request already accepted by the backend when
    // its response has not yet arrived.
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b0;
    pprot = 3'b000;
    paddr = 12'h04C;
    pwdata = '0;
    pstrb = '0;
    request_ready = 1'b1;
    response_valid = 1'b0;
    tick();
    @(negedge clk);
    penable = 1'b1;
    #1;
    require(request_valid && request_ready && response_ready && !pready,
            "Backend must accept the request while its response is pending");
    tick();
    require(!request_valid && response_ready && !pready,
            "Accepted request must wait for its backend response");
    repeat (2) begin
      tick();
      require(!request_valid && response_ready && !pready,
              "Response wait must not reissue the accepted backend request");
    end

    @(negedge clk);
    rst_n = 1'b0;
    psel = 1'b0;
    penable = 1'b0;
    #1;
    require(!request_valid && !response_ready && !pready && !pslverr &&
            prdata == '0,
            "Reset must cancel an accepted request awaiting its response");
    repeat (2) tick();
    rst_n = 1'b1;
    tick();
    require(!request_valid && !response_ready && !pready && !pslverr,
            "Endpoint must remain idle after reset releases a pending response");

    psel = 1'b0;
    penable = 1'b0;
    $display("PASS: TSN Qbv APB endpoint request/response behavior");
    $finish;
  end

endmodule : tsn_qbv_apb_endpoint_tb
