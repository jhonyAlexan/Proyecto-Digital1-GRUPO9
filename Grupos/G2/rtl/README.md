# Implementación RTL y Verificación - Memorias 

En esta carpeta reunimos el código sintetizable en Verilog, las restricciones físicas de pines y el banco de pruebas autoverificado del subsistema de memorias para la **Sipeed Tang Nano 9K** (FPGA Gowin GW1NR-9, reloj maestro de $27\text{ MHz}$).

## 1. Estructura de Archivos

```text
Grupos/G2/rtl/
├── README.md                 # Esta guía técnica del directorio RTL
├── spi_flash_controller.v    # Núcleo maestro SPI Modo 0 bajo metodología FSMD
├── peripheral_spi_flash.v    # Adaptador MMIO de 32 bits (región 0x0045_0000 - 0x0045_000C)
├── bram_prog_data.v          # RAM principal de 32 KB (BSRAM) + 6 registros de controles (42..47)
├── g2_mem_top.v              # Envoltorio estructural opcional para conectar ambos módulos al SoC
├── g2_flash.cst              # Asignación de pines físicos de la Flash SPI en la Tang Nano 9K
├── Makefile                  # Automatización de compilación y simulación con Icarus Verilog
└── tb/
    └── tb_spi_flash.v        # Banco de pruebas autoverificado (traza transiciones T0-T12)
