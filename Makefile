# Make sure /bin/bash is used for the 'find' in clean
SHELL := /bin/bash

.PHONY: test run clean

# Run all tests (no args). Test code itself lives in the Tests
# submodule (insper-riscv/RISC-V-Workstation-Tests), not here — run
# `git submodule update --init --recursive` first if Tests/ is empty.
test:
	python3 Tests/tests/python/runner.py

# Run a single test by name
# Usage: make run TEST=<test_name>
run:
ifndef TEST
	$(error Usage: make run TEST=<test_name>)
endif
	python3 Tests/tests/python/runner.py $(TEST)

# Remove generated waveforms
clean:
	find . -type f \( -name '*.vcd' -o -name '*.ghw' \) -print -delete


# ---------------------------------------------------------------
# VHDL Syntax Check (GHDL)
# Run with:  make check
# ---------------------------------------------------------------
GHDL := ghdl
STD  := --std=08
WDIR := build/ghdl

# 1) Coleta todos .vhd/.vhdl
CHECK_SRCS_ALL := $(shell find src -type f \( -name '*.vhd' -o -name '*.vhdl' \) | sort)

# 2) EXCLUI vendors/IPs e arquivos que usam bibliotecas Intel (lpm, altera)
EXCLUDE_GLOB := \
  src/ROM1PORT/% \
  src/RAM1PORT/% \
  src/ROM_IP/% \
  src/%/ip/% \
  src/%/quartus_ip/% \
  src/**/ip/% \
  src/**/quartus_ip/% \
  src/RV32M.vhd \
  src/mhu.vhd \
  src/rv32im_pipeline_fpga_top.vhd

CHECK_SRCS := $(filter-out $(EXCLUDE_GLOB),$(CHECK_SRCS_ALL))

# 3) Ordena automaticamente por dependencias (topological sort)
ORDERED_SRCS := $(shell python3 tools/vhdl_topo_sort.py $(CHECK_SRCS))

.PHONY: print-check check
print-check:
	@echo "Arquivos que o check vai analisar:"; echo
	@printf '  %s\n' $(ORDERED_SRCS)

check:
	@echo "🔍 Checking VHDL syntax with GHDL..."
	@mkdir -p $(WDIR)
	@rm -rf $(WDIR)/*
	@$(GHDL) -a $(STD) --work=work --workdir=$(WDIR) $(ORDERED_SRCS)
	@echo "✅ VHDL syntax check passed"
