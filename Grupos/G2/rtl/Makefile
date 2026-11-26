# ============================================================================
# Archivo: Grupos/G2/rtl/Makefile
# Descripción: Automatización de simulación (Icarus Verilog / GTKWave) y
#              verificación de síntesis (Yosys + nextpnr) para Subgrupo G2.
# ============================================================================

# Herramientas del flujo abierto
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave
YOSYS    = yosys
NEXTPNR  = nextpnr-himbaechel
PACK     = gowin_pack

# Parámetros de la FPGA Sipeed Tang Nano 9K
DEVICE   = GW1NR-LV9QN88PC6/I5
FAMILY   = GW1N-9C
TOP      = g2_mem_top
TB_TOP   = tb_spi_flash

# Directorio de artefactos temporales (no subir al repositorio)
BUILD_DIR = build

# Archivos fuente RTL del Subgrupo G2
RTL_SRCS = \
	spi_flash_controller.v \
	peripheral_spi_flash.v \
	bram_prog_data.v \
	g2_mem_top.v

TB_SRCS = tb/tb_spi_flash.v
CST     = g2_flash.cst

VVP_OUT = $(BUILD_DIR)/$(TB_TOP).vvp
VCD_OUT = $(TB_TOP).vcd

.PHONY: all sim wave lint synth clean help

all: sim

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ----------------------------------------------------------------------------
# 1. Simulación autoverificada con Icarus Verilog
# ----------------------------------------------------------------------------
$(VVP_OUT): $(RTL_SRCS) $(TB_SRCS) | $(BUILD_DIR)
	$(IVERILOG) -g2005 -Wall -s $(TB_TOP) -o $(VVP_OUT) $(RTL_SRCS) $(TB_SRCS)

sim: $(VVP_OUT)
	$(VVP) $(VVP_OUT)

# ----------------------------------------------------------------------------
# 2. Visualización de formas de onda en GTKWave
# ----------------------------------------------------------------------------
wave: sim
	$(GTKWAVE) $(VCD_OUT) &

# ----------------------------------------------------------------------------
# 3. Chequeo de síntesis y detección de latches con Yosys
# ----------------------------------------------------------------------------
lint: $(RTL_SRCS) | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog $(RTL_SRCS); hierarchy -check -top $(TOP); proc; opt; check -assert"

# ----------------------------------------------------------------------------
# 4. Síntesis y Place & Route aislado para validar g2_flash.cst
#    Nota: Para síntesis aislada de g2_mem_top, descomentar clk y rst en g2_flash.cst
# ----------------------------------------------------------------------------
synth: $(RTL_SRCS) $(CST) | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog $(RTL_SRCS); synth_gowin -top $(TOP) -json $(BUILD_DIR)/$(TOP).json"
	$(NEXTPNR) --json $(BUILD_DIR)/$(TOP).json --write $(BUILD_DIR)/$(TOP)_pnr.json \
		--device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)
	$(PACK) -d $(FAMILY) --use_mspi_as_gpio -o $(BUILD_DIR)/$(TOP).fs $(BUILD_DIR)/$(TOP)_pnr.json

# ----------------------------------------------------------------------------
# 5. Limpieza de archivos temporales de simulación y síntesis
# ----------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) $(VCD_OUT)

help:
	@echo "Objetivos disponibles en Grupos/G2/rtl/:"
	@echo "  make sim   - Compila con iverilog y ejecuta tb_spi_flash (PASA/FALLA)"
	@echo "  make wave  - Ejecuta la simulacion y abre tb_spi_flash.vcd en GTKWave"
	@echo "  make lint  - Verifica jerarquia y ausencia de latches en Yosys"
	@echo "  make synth - Sintetiza y empaqueta bitstream con --use_mspi_as_gpio"
	@echo "  make clean - Elimina build/ y archivos temporales .vvp/.vcd"
