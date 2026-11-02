package tsn_qbv_apb_types_pkg;

  localparam int unsigned ApbAddressWidth = 12;
  localparam int unsigned ApbDataWidth = 32;
  localparam int unsigned ApbStrobeWidth = ApbDataWidth / 8;
  localparam int unsigned ApbProtectionWidth = 3;

  typedef logic [ApbAddressWidth-1:0] tsn_qbv_apb_addr_t;
  typedef logic [ApbDataWidth-1:0] tsn_qbv_apb_data_t;
  typedef logic [ApbStrobeWidth-1:0] tsn_qbv_apb_strb_t;
  typedef logic [ApbProtectionWidth-1:0] tsn_qbv_apb_prot_t;

endpackage : tsn_qbv_apb_types_pkg
