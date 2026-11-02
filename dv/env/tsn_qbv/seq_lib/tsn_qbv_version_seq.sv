// SPDX-License-Identifier: Apache-2.0

class tsn_qbv_version_seq extends apb_master_base_seq #(
  tsn_qbv_apb_types_pkg::ApbAddressWidth,
  tsn_qbv_apb_types_pkg::ApbDataWidth
);

  typedef apb_master_item #(
    tsn_qbv_apb_types_pkg::ApbAddressWidth,
    tsn_qbv_apb_types_pkg::ApbDataWidth
  ) item_t;

  `uvm_object_utils(tsn_qbv_version_seq)
  `uvm_object_new

  virtual task body();
    item_t item;

    item = item_t::type_id::create("item");
    item.we = 1'b0;
    item.addr = tsn_qbv_apb_pkg::AddrVersion;
    item.wdata = '0;
    item.strb = '0;
    item.prot = '0;
    item.nse = 1'b0;
    item.wakeup = 1'b0;
    item.auser = '0;
    item.wuser = '0;
    send_item_no_rand(item);

    if (item.slverr !== 1'b0) begin
      `uvm_fatal(`gfn, $sformatf("Version read returned PSLVERR: %s", item.convert2string()))
    end
    if (item.rdata !== tsn_qbv_apb_pkg::Version) begin
      `uvm_fatal(`gfn, $sformatf(
        "Version mismatch: got 0x%08h expected 0x%08h",
        item.rdata, tsn_qbv_apb_pkg::Version))
    end
    `uvm_info(`gfn, $sformatf("Version read PASS: 0x%08h", item.rdata), UVM_LOW)
  endtask : body

endclass : tsn_qbv_version_seq
