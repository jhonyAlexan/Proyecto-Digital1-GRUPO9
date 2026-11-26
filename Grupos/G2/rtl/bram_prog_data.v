// ============================================================================
// Módulo: Grupos/G2/rtl/bram_prog_data.v
// Descripción: Memoria principal de programa y datos de 32 KB (8192 x 32 bits)
//              inferida en BSRAM interna para FemtoRV32.
// Rango MMIO: 0x0000_0000 - 0x0000_7FFF (sin palabras reservadas de mandos).
// ============================================================================

module bram_prog_data #(
    parameter integer WORDS     = 8192, // 32 KB = 8192 palabras de 32 bits
    parameter         INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        cs,
    input  wire        rd,
    input  wire [3:0]  wmask,
    input  wire [14:2] word_addr,
    input  wire [31:0] d_in,
    output reg  [31:0] d_out
);

    (* ram_style = "block" *) reg [31:0] mem [0:WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (cs) begin
            if (wmask[0]) mem[word_addr][7:0]   <= d_in[7:0];
            if (wmask[1]) mem[word_addr][15:8]  <= d_in[15:8];
            if (wmask[2]) mem[word_addr][23:16] <= d_in[23:16];
            if (wmask[3]) mem[word_addr][31:24] <= d_in[31:24];
            if (rd)
                d_out <= mem[word_addr];
        end
    end

endmodule
