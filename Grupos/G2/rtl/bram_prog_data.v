// ============================================================================
// Módulo: bram_prog_data.v
// Descripción: Memoria principal de programa y datos de 32 KB (8192 x 32 bits)
//              inferida en BSRAM interna para FemtoRV32. Incluye puertos de
//              actualización directa para los 6 registros de controles (42..47).
// Rango MMIO: 0x0000_0000 - 0x0000_7FFF
// ============================================================================

module bram_prog_data #(
    parameter integer WORDS      = 8192, // 32 KB = 8192 palabras de 32 bits
    parameter         INIT_FILE  = ""    // Archivo .hex opcional para firmware
) (
    input  wire        clk,
    // Bus principal del procesador FemtoRV32
    input  wire        cs,
    input  wire        rd,
    input  wire [3:0]  wmask,
    input  wire [14:2] word_addr,
    input  wire [31:0] d_in,
    output reg  [31:0] d_out,
    // Actualización directa de los 6 registros reservados de controles (42..47)
    input  wire        ctrl_we,
    input  wire [2:0]  ctrl_idx,   // 0..5 -> direcciones de palabra 42..47
    input  wire [31:0] ctrl_data
);

    (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Escritura por bytes (wmask[3:0]) desde CPU o escritura desde receptor de controles
    wire [12:0] eff_addr  = ctrl_we ? (13'd42 + {10'd0, ctrl_idx}) : word_addr;
    wire [3:0]  eff_wmask = ctrl_we ? 4'b1111 : (cs ? wmask : 4'b0000);
    wire [31:0] eff_din   = ctrl_we ? ctrl_data : d_in;

    always @(posedge clk) begin
        if (eff_wmask[0]) mem[eff_addr][7:0]   <= eff_din[7:0];
        if (eff_wmask[1]) mem[eff_addr][15:8]  <= eff_din[15:8];
        if (eff_wmask[2]) mem[eff_addr][23:16] <= eff_din[23:16];
        if (eff_wmask[3]) mem[eff_addr][31:24] <= eff_din[31:24];

        if (cs && rd)
            d_out <= mem[word_addr];
    end

endmodule
