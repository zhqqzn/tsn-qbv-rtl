module tsn_qbv_apb_reg_map_tb;

  logic checked;

  tsn_qbv_apb_reg_map_checker u_checker (
    .checked_o(checked)
  );

  initial begin
    wait (checked);
    $display("PASS: TSN Qbv APB register map alignment and uniqueness");
    $finish;
  end

endmodule : tsn_qbv_apb_reg_map_tb
