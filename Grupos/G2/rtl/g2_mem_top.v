// ============================================================================
// Archivo: Grupos/G2/rtl/g2_mem_top.v
// Descripción: Envoltorio estructural del subsistema de memorias (Subgrupo G2).
//              Integra:
//              1) bram_prog_data: RAM principal de 32 KB (0x0000_0000 - 0x0000_7FFF)
//                 + 6 registros reservados para controles (direcciones 42..47).
//              2) peripheral_spi_flash: Controlador Flash SPI W25Q64JV en Modo 0
//                 mapeado en 0x0045_0000 - 0x0045_000C (región 0x0045).
// ============================================================================

module g2_mem_top #(
    parameter integer RAM_WORDS     = 8192, // 32 KB (8192 palabras de 32 bits)
    parameter         RAM_INIT_FILE = "",   // Ruta al archivo firmware.hex
    parameter integer SPI_TICK_DIV  = 4     // f_SCLK = 27 MHz / (2*4) = 3.375 MHz
) (
    input  wire        clk,        // Reloj maestro del SoC (27 MHz)
    input  wire        rst,        // Reinicio síncrono activo en alto (!resetn)

    // Bus estándar del procesador FemtoRV32
    input  wire [31:0] mem_addr,   // Dirección de byte desde CPU
    input  wire [31:0] mem_wdata,  // Datos de escritura desde CPU
    input  wire [3:0]  mem_wmask,  // Máscara de escritura por byte
    input  wire        rd,         // Habilitación de lectura (mem_rstrb)

    // Selecciones de región desde chip_select del SoC
    input  wire        cs_ram,     // Activo cuando mem_addr[31:16] == 16'h0000
    input  wire        cs_flash,   // Activo cuando mem_addr[31:16] == 16'h0045

    // Buses de lectura hacia el multiplexor mem_rdata del SoC
    output wire [31:0] ram_dout,   // Salida de lectura de BRAM_PROG_DATA
    output wire [31:0] flash_dout, // Salida de lectura de SPI_FLASH_CTRL

    // Puerto de actualización directa para los 6 registros de controles (42..47)
    input  wire        ctrl_we,    // Habilitación de escritura desde receptor mando
    input  wire [2:0]  ctrl_idx,   // Índice 0..5 -> direcciones de palabra 42..47
    input  wire [31:0] ctrl_data,  // Valor actualizado del eje o botón

    // Pines físicos SPI Modo 0 hacia memoria externa Winbond W25Q64JV
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // Acota el acceso de BRAM_PROG_DATA estrictamente a los primeros 32 KB
    // (0x0000_0000 - 0x0000_7FFF), evitando solapamiento en 0x0000_8000..0xFFFF.
    wire cs_ram_valid = cs_ram && !mem_addr[15];

    // 1. Memoria principal de instrucciones/datos y registros de controles
    bram_prog_data #(
        .WORDS     (RAM_WORDS),
        .INIT_FILE (RAM_INIT_FILE)
    ) u_bram_prog_data (
        .clk       (clk),
        .cs        (cs_ram_valid),
        .rd        (rd),
        .wmask     (mem_wmask),
        .word_addr (mem_addr[14:2]),
        .d_in      (mem_wdata),
        .d_out     (ram_dout),
        .ctrl_we   (ctrl_we),
        .ctrl_idx  (ctrl_idx),
        .ctrl_data (ctrl_data)
    );

    // 2. Periférico MMIO del Controlador Flash SPI (Base 0x0045_0000)
    peripheral_spi_flash #(
        .TICK_DIV (SPI_TICK_DIV)
    ) u_peripheral_spi_flash (
        .clk      (clk),
        .rst      (rst),
        .cs       (cs_flash),
        .rd       (rd),
        .addr     (mem_addr),
        .d_in     (mem_wdata),
        .wmask    (mem_wmask),
        .d_out    (flash_dout),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

endmodule
