.PHONY: test-model test-configuration test-runtime lint-rtl test-rtl

VERILATOR ?= verilator
VERILATOR_MDIR ?= .build/verilator/tsn_qbv_list_execute
VERILATOR_LIST_CONFIG_MDIR ?= .build/verilator/tsn_qbv_list_config
VERILATOR_CYCLE_TIMER_MDIR ?= .build/verilator/tsn_qbv_cycle_timer
VERILATOR_TSN_QBV_MDIR ?= .build/verilator/tsn_qbv
VERILATOR_CONFIG_TIME_MDIR ?= .build/verilator/config_change_time
VERILATOR_APB_REG_MAP_MDIR ?= .build/verilator/tsn_qbv_apb_reg_map
VERILATOR_APB_ENDPOINT_MDIR ?= .build/verilator/tsn_qbv_apb_endpoint
VERILATOR_APB_ADMIN_STAGE_MDIR ?= .build/verilator/tsn_qbv_apb_admin_stage
VERILATOR_APB_ADMIN_REGS_MDIR ?= .build/verilator/tsn_qbv_apb_admin_registers
VERILATOR_APB_MDIR ?= .build/verilator/tsn_qbv_apb
VERILATOR_APB_SINGLE_ENTRY_MDIR ?= .build/verilator/tsn_qbv_apb_single_entry

# Python reference model: executable contract for the Qbv port behavior.
test-model:
	PYTHONPATH=dv/reference_model python3 -m unittest discover \
		-s dv/reference_model/tests -v

test-configuration:
	PYTHONPATH=dv/reference_model python3 -m unittest discover \
		-s dv/reference_model/tests -p 'test_configuration.py' -v

test-runtime:
	PYTHONPATH=dv/reference_model python3 -m unittest discover \
		-s dv/reference_model/tests -p 'test_runtime.py' -v

# RTL and directed DV source lint. Verilator is the initial supported open-source frontend.
lint-rtl:
	command -v $(VERILATOR)
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_list_execute \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_gcl_store \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_list_config \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_cycle_timer \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_config_change_time \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_reg_map_tb \
		-f dv/tb/apb_reg_map_files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_endpoint \
		-f dv/tb/apb_endpoint_files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_admin_stage_tb \
		-f dv/tb/apb_admin_stage_tb_files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_admin_registers_tb \
		-f dv/tb/apb_admin_registers_files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv \
		-f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_tb \
		-f dv/tb/tb_files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module tsn_qbv_apb_single_entry_tb \
		-f dv/tb/tsn_qbv_apb_single_entry_tb_files.f

# Directed block-level and integration simulations.
test-rtl:
	command -v $(VERILATOR)
	mkdir -p "$(VERILATOR_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_list_execute_tb \
		--Mdir "$(VERILATOR_MDIR)" -f dv/tb/list_execute_files.f
	"$(VERILATOR_MDIR)/Vtsn_qbv_list_execute_tb"
	mkdir -p "$(VERILATOR_LIST_CONFIG_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_list_config_tb \
		--Mdir "$(VERILATOR_LIST_CONFIG_MDIR)" -f dv/tb/list_config_files.f
	"$(VERILATOR_LIST_CONFIG_MDIR)/Vtsn_qbv_list_config_tb"
	mkdir -p "$(VERILATOR_CYCLE_TIMER_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_cycle_timer_tb \
		--Mdir "$(VERILATOR_CYCLE_TIMER_MDIR)" -f dv/tb/cycle_timer_files.f
	"$(VERILATOR_CYCLE_TIMER_MDIR)/Vtsn_qbv_cycle_timer_tb"
	mkdir -p "$(VERILATOR_CONFIG_TIME_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_config_change_time_tb \
		--Mdir "$(VERILATOR_CONFIG_TIME_MDIR)" -f dv/tb/config_change_time_files.f
	"$(VERILATOR_CONFIG_TIME_MDIR)/Vtsn_qbv_config_change_time_tb"
	mkdir -p "$(VERILATOR_APB_REG_MAP_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_reg_map_tb \
		--Mdir "$(VERILATOR_APB_REG_MAP_MDIR)" -f dv/tb/apb_reg_map_files.f
	"$(VERILATOR_APB_REG_MAP_MDIR)/Vtsn_qbv_apb_reg_map_tb"
	mkdir -p "$(VERILATOR_APB_ENDPOINT_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_endpoint_tb \
		--Mdir "$(VERILATOR_APB_ENDPOINT_MDIR)" -f dv/tb/apb_endpoint_tb_files.f
	"$(VERILATOR_APB_ENDPOINT_MDIR)/Vtsn_qbv_apb_endpoint_tb"
	mkdir -p "$(VERILATOR_APB_ADMIN_STAGE_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_admin_stage_tb \
		--Mdir "$(VERILATOR_APB_ADMIN_STAGE_MDIR)" -f dv/tb/apb_admin_stage_tb_files.f
	"$(VERILATOR_APB_ADMIN_STAGE_MDIR)/Vtsn_qbv_apb_admin_stage_tb"
	mkdir -p "$(VERILATOR_APB_ADMIN_REGS_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_admin_registers_tb \
		--Mdir "$(VERILATOR_APB_ADMIN_REGS_MDIR)" -f dv/tb/apb_admin_registers_files.f
	"$(VERILATOR_APB_ADMIN_REGS_MDIR)/Vtsn_qbv_apb_admin_registers_tb"
	mkdir -p "$(VERILATOR_APB_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_tb \
		--Mdir "$(VERILATOR_APB_MDIR)" -f dv/tb/tb_files.f
	"$(VERILATOR_APB_MDIR)/Vtsn_qbv_apb_tb"
	mkdir -p "$(VERILATOR_APB_SINGLE_ENTRY_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_apb_single_entry_tb \
		--Mdir "$(VERILATOR_APB_SINGLE_ENTRY_MDIR)" -f dv/tb/tsn_qbv_apb_single_entry_tb_files.f
	"$(VERILATOR_APB_SINGLE_ENTRY_MDIR)/Vtsn_qbv_apb_single_entry_tb"
	mkdir -p "$(VERILATOR_TSN_QBV_MDIR)"
	$(VERILATOR) --binary --timing --assert -Wall --timescale 1ns/1ps \
		--top-module tsn_qbv_tb \
		--Mdir "$(VERILATOR_TSN_QBV_MDIR)" -f dv/tb/tsn_qbv_files.f
	"$(VERILATOR_TSN_QBV_MDIR)/Vtsn_qbv_tb"
