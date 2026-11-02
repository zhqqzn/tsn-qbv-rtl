// SPDX-License-Identifier: Apache-2.0

class tsn_qbv_version_test extends tsn_qbv_base_test;

  typedef apb_master_item #(
    tsn_qbv_apb_types_pkg::ApbAddressWidth,
    tsn_qbv_apb_types_pkg::ApbDataWidth
  ) observed_item_t;

  `uvm_component_utils(tsn_qbv_version_test)
  `uvm_component_new

  virtual protected task run_vseqs();
    tsn_qbv_version_seq seq;
    observed_item_t observed;

    seq = tsn_qbv_version_seq::type_id::create("seq");
    `DV_CHECK_RANDOMIZE_FATAL(seq)
    seq.start(env.apb_master.sequencer);

    env.apb_observed_fifo.get(observed);
    if (observed.addr !== tsn_qbv_apb_pkg::AddrVersion ||
        observed.we !== 1'b0 ||
        observed.slverr !== 1'b0 ||
        observed.rdata !== tsn_qbv_apb_pkg::Version) begin
      `uvm_fatal(`gfn, $sformatf(
        "APB monitor mismatch: %s; expected read 0x%03h -> 0x%08h",
        observed.convert2string(), tsn_qbv_apb_pkg::AddrVersion,
        tsn_qbv_apb_pkg::Version))
    end
    `uvm_info(`gfn, "APB monitor observed the Version read: PASS", UVM_LOW)
  endtask : run_vseqs

endclass : tsn_qbv_version_test
