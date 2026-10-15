# Tools live in .tools/ inside the project (Claude Code sandbox boundary)
OSS_CAD ?= $(CURDIR)/.tools/oss-cad-suite
export PATH := $(OSS_CAD)/bin:$(PATH)
# Full paths: macOS GNU Make 3.81 looks up the program of a simple recipe in the old PATH,
# ignoring the export above (PATH itself is still needed by child processes and make sim)
VERILATOR      := $(OSS_CAD)/bin/verilator
YOSYS          := $(OSS_CAD)/bin/yosys
NEXTPNR        := $(OSS_CAD)/bin/nextpnr-himbaechel
GOWIN_PACK     := $(OSS_CAD)/bin/gowin_pack
OPENFPGALOADER := $(OSS_CAD)/bin/openFPGALoader
GTKWAVE        := $(OSS_CAD)/bin/gtkwave

# Design: demo/$(DEMO) with demo.mk (TOP, SOURCES, CST, TEST, SIM_PARAMS)
DEMO      ?= blinky
DEMO_DIR  := $(CURDIR)/demo/$(DEMO)
BUILD_DIR := $(CURDIR)/build/$(DEMO)
ifeq ($(wildcard $(DEMO_DIR)/demo.mk),)
$(error No demo/$(DEMO)/demo.mk; available: $(notdir $(wildcard demo/*)))
endif
include $(DEMO_DIR)/demo.mk
SRCS     := $(addprefix $(DEMO_DIR)/,$(SOURCES))
CST_FILE := $(DEMO_DIR)/$(CST)
FS       := $(BUILD_DIR)/$(TOP).fs

BOARD  := tangnano9k
DEVICE := GW1NR-LV9QN88PC6/I5
FAMILY := GW1N-9C
# On-board oscillator, MHz (timing target for nextpnr)
FREQ   := 27

.PHONY: all check-tools demos sim lint build waves flash-sram flash-perm detect clean clean-all
all: build

# Verify downloads/ and .tools/ against tools.lock; extracts the archive if .tools/ is missing
check-tools:
	bash scripts/check_tools.sh tools.lock downloads $(OSS_CAD)

demos:
	@for d in demo/*/demo.mk; do n=$${d#demo/}; echo "$${n%/demo.mk}"; done

# 0. Lint
lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) $(SRCS)

# 1. cocotb simulation (cocotb and Python from OSS CAD Suite); runs in the design dir so the test module is found
sim:
	PYTHONDONTWRITEBYTECODE=1 $(MAKE) -C $(DEMO_DIR) -f $(CURDIR)/Makefile.sim \
		DEMO_TOP=$(TOP) DEMO_TEST=$(TEST) DEMO_SOURCES="$(SRCS)" \
		DEMO_SIM_ARGS="$(addprefix -P$(TOP).,$(SIM_PARAMS))" \
		SIM_BUILD=$(BUILD_DIR)/sim_build COCOTB_RESULTS_FILE=$(BUILD_DIR)/results.xml

# Waveforms of the last simulation
waves:
	$(GTKWAVE) $(BUILD_DIR)/sim_build/$(TOP).fst

# 2. Synthesis (Yosys) -> place & route (nextpnr-himbaechel, gowin) -> bitstream (gowin_pack)
build: $(FS)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/$(TOP).json: $(SRCS) $(DEMO_DIR)/demo.mk | $(BUILD_DIR)
	$(YOSYS) -q -l $(BUILD_DIR)/yosys.log -p "read_verilog -sv $(SRCS); synth_gowin -top $(TOP) -json $@"

$(BUILD_DIR)/$(TOP)_pnr.json: $(BUILD_DIR)/$(TOP).json $(CST_FILE)
	$(NEXTPNR) --json $< --write $@ --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST_FILE) \
		--freq $(FREQ) -l $(BUILD_DIR)/nextpnr.log

$(FS): $(BUILD_DIR)/$(TOP)_pnr.json
	$(GOWIN_PACK) -d $(FAMILY) -o $@ $<

# 3. Board (openFPGALoader)
detect:
	$(OPENFPGALOADER) --detect

flash-sram: $(FS)
	$(OPENFPGALOADER) -b $(BOARD) $<

flash-perm: $(FS)
	$(OPENFPGALOADER) -b $(BOARD) -f $<

# 4. Clean: clean = current design, clean-all = everything
clean:
	rm -rf $(BUILD_DIR)

clean-all:
	rm -rf build
