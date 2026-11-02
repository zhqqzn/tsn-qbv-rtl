// SPDX-License-Identifier: Apache-2.0

class tsn_qbv_env_cfg extends base_env_cfg;

  rand apb_master_agent_cfg apb_master_cfg;
  // slang lint_save
  // slang lint_off case-default
  // slang lint_off empty-stmt
  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off WIDTHEXPAND */
  /* verilator lint_off WIDTHTRUNC */
  /* verilator lint_off VARHIDDEN */
  `uvm_object_utils_begin(tsn_qbv_env_cfg)
    `uvm_field_object(apb_master_cfg, UVM_DEFAULT)
  `uvm_object_utils_end
  /* verilator lint_on VARHIDDEN */
  /* verilator lint_on WIDTHTRUNC */
  /* verilator lint_on WIDTHEXPAND */
  /* verilator lint_on UNUSEDSIGNAL */
  // slang lint_restore
  function new(string name = "");
    super.new(name);
    apb_master_cfg = apb_master_agent_cfg::type_id::create({`gfn, ".apb_master_cfg"});
    apb_master_cfg.bus_cfg.set_version(apb_bus_cfg::ApbVersion4);
    en_scb = 1'b0;
  endfunction : new

endclass : tsn_qbv_env_cfg
