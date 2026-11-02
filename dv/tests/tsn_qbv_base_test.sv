// SPDX-License-Identifier: Apache-2.0

class tsn_qbv_base_test extends base_test #(
  .ENV_T(tsn_qbv_env),
  .ENV_CFG_T(tsn_qbv_env_cfg)
);

  `uvm_component_utils(tsn_qbv_base_test)
  `uvm_component_new

endclass : tsn_qbv_base_test
