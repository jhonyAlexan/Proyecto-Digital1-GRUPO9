// ============================================================================
// Modulo: Grupos/G2/rtl/g2_mem_top.v
// Descripción: Envoltorio estructural del subsistema de memorias (Subgrupo G2).
//              Integra:
//              1) bram_prog_data: RAM principal de 32 KB (0x0000_0000 - 0x0000_7FFF)
//                 + 6 registros reservados para controles (direcciones 42..47).
//              2) peripheral_spi_flash: Controlador Flash SPI W25Q64JV en Modo 0
//                 mapeado en 0x0045_0000 - 0x0045_000C (región 0x0045).
// ============================================================================


module g2_mem_top #(
    parameter integer RAM_WORDS     = 8192,
    parameter         RAM_INIT_FILE = "",
    parameter integer SPI_TICK_DIV  = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wmask,
    input  wire        rd,
    input  wire        cs_ram,     // Activo cuando mem_addr[31:16] == 16'h0000
    input  wire        cs_flash,   // Activo cuando mem_addr[31:16] == 16'h0045
    output wire [31:0] ram_dout,
    output wire [31:0] flash_dout,
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    wire cs_ram_valid = cs_ram && (mem_addr[31:15] == 17'd0);

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
        .d_out     (ram_dout)
    );

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
