// SPDX-License-Identifier: Apache-2.0

class tsn_qbv_env extends base_env #(
  .CFG_T(tsn_qbv_env_cfg)
);

  `uvm_component_utils(tsn_qbv_env)

  apb_master_agent #(
    tsn_qbv_apb_types_pkg::ApbAddressWidth,
    tsn_qbv_apb_types_pkg::ApbDataWidth
  ) apb_master;
  uvm_tlm_analysis_fifo #(
    apb_master_item #(
      tsn_qbv_apb_types_pkg::ApbAddressWidth,
      tsn_qbv_apb_types_pkg::ApbDataWidth
    )
  ) apb_observed_fifo;

  `uvm_component_new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_config_db #(apb_master_agent_cfg)::set(
      this, "apb_master*", "cfg", cfg.apb_master_cfg);
    apb_master = apb_master_agent #(
      tsn_qbv_apb_types_pkg::ApbAddressWidth,
      tsn_qbv_apb_types_pkg::ApbDataWidth
    )::type_id::create("apb_master", this);
    apb_observed_fifo = new("apb_observed_fifo", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    apb_master.ap.connect(apb_observed_fifo.analysis_export);
  endfunction : connect_phase

endclass : tsn_qbv_env
