// =============================================================================
// peripheral_hub75.v — Adaptador MMIO entre FemtoRV32 Quark y hub75_core
//
// Sigue el patrón del periférico UART8N1 de la guía uart-riscv.pdf (cap. 12):
//   1. peripheral_hub75_addr_decoder     (combinacional) cs + addr[15:0] -> sel
//   2. peripheral_hub75_register_control (secuencial)    registros y d_out
//   3. hub75_core                        framebuffer, ticks, control y datapath
//
// Región: chip_select la elige con mem_addr[31:16] = 0x0044 (chip 4).
// Mapa (offset = addr[15:0]):
//
//   0x0000          CONTROL  RW  [0] EN (reset 0)
//   0x0004          BRIGHT   RW  [9:0] ticks con OE activo por fila (reset 512)
//   0x0008          STATUS   R   [0] BUSY = barrido activo
//   0x000C          —        reservado, se lee 0
//   0x0010          FRAME    R   [31:0] cuadros completos mostrados
//   0x4000-0x7FFC   FB       W   ventana del framebuffer: píxel (x, y) en
//                                0x4000 + 4 * (64 * y + x), dato [2:0] = {R,G,B}
//
// Escritura: tiene efecto con wmask[0] = 1 (un sw trae wmask = 1111).
// Lectura:   d_out se captura en el flanco con cs y rd activos y se conserva
//            hasta la siguiente lectura (Quark pide el dato en EXECUTE y lo usa
//            en WAIT, cuando rd ya bajó).
//
// Uso de IA: elaborado con ayuda de un asistente de IA (Claude) a partir de los
// diagramas y la tabla de transferencias del README de G4; revisado y probado por el grupo.
// =============================================================================
module peripheral_hub75 #(
    parameter CLK_DIV       = 2,
    parameter DISPLAY_TICKS = 1024
) (
    input  wire        clk,
    input  wire        rst,

    // Bus de FemtoRV32 Quark
    input  wire        cs,
    input  wire        rd,          // mem_rstrb
    input  wire [31:0] addr,        // mem_addr (se usa [15:0])
    input  wire [31:0] d_in,        // mem_wdata
    input  wire [ 3:0] wmask,       // mem_wmask
    output wire [31:0] d_out,       // hacia chip_select -> mem_rdata

    // Conector HUB75
    output wire [ 2:0] hub75_rgb0,
    output wire [ 2:0] hub75_rgb1,
    output wire [ 4:0] hub75_row,
    output wire        hub75_clk,
    output wire        hub75_lat,
    output wire        hub75_oe
);

    wire [4:0]  sel;               // {FB, FRAME, STATUS, BRIGHT, CONTROL}
    wire        enable;
    wire [9:0]  brightness;
    wire        fb_we;
    wire [11:0] fb_waddr;
    wire [2:0]  fb_wdata;
    wire        busy;
    wire [31:0] frame_count;

    peripheral_hub75_addr_decoder u_dec (
        .cs(cs), .addr(addr[15:0]), .sel(sel)
    );

    peripheral_hub75_register_control u_regs (
        .clk(clk), .rst(rst),
        .cs(cs), .rd(rd), .sel(sel), .addr(addr[13:2]),
        .d_in(d_in), .wmask0(wmask[0]), .d_out(d_out),
        .busy(busy), .frame_count(frame_count),
        .enable(enable), .brightness(brightness),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata)
    );

    hub75_core #(.CLK_DIV(CLK_DIV), .DISPLAY_TICKS(DISPLAY_TICKS)) u_core (
        .clk(clk), .rst(rst),
        .enable(enable), .brightness(brightness),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .busy(busy), .frame_count(frame_count),
        .hub75_rgb0(hub75_rgb0), .hub75_rgb1(hub75_rgb1), .hub75_row(hub75_row),
        .hub75_clk(hub75_clk), .hub75_lat(hub75_lat), .hub75_oe(hub75_oe)
    );

endmodule


// =============================================================================
// Decodificador local (combinacional): selección one-hot del registro.
// Con cs = 0, o con un offset que no corresponde a nada, sel = 0.
// =============================================================================
module peripheral_hub75_addr_decoder (
    input  wire        cs,
    input  wire [15:0] addr,
    output reg  [ 4:0] sel          // {FB, FRAME, STATUS, BRIGHT, CONTROL}
);
    always @(*) begin
        sel = 5'b00000;
        if (cs) begin
            if (addr[15:14] == 2'b01)  sel = 5'b10000;   // ventana del framebuffer
            else case (addr)
                16'h0000: sel = 5'b00001;               // CONTROL
                16'h0004: sel = 5'b00010;               // BRIGHT
                16'h0008: sel = 5'b00100;               // STATUS
                16'h0010: sel = 5'b01000;               // FRAME
                default:  sel = 5'b00000;               // 0x000C reservado y otros
            endcase
        end
    end
endmodule


// =============================================================================
// Control de registros (secuencial).
//   Escritura: CONTROL <- d_in[0] con sel[0] y wmask[0]
//              BRIGHT  <- d_in[9:0] con sel[1] y wmask[0]
//              píxel: fb_we = sel[4] y wmask[0], fb_waddr = addr[13:2],
//                     fb_wdata = d_in[2:0], en el mismo flanco del acceso
//   Lectura:   con cs y rd, d_out captura el registro elegido (0 para la
//              ventana del framebuffer, el reservado o uno no válido) y lo
//              conserva mientras no haya otra lectura.
// =============================================================================
module peripheral_hub75_register_control (
    input  wire        clk,
    input  wire        rst,
    input  wire        cs,
    input  wire        rd,
    input  wire [ 4:0] sel,
    input  wire [11:0] addr,        // addr[13:2] = {y, x} en la ventana
    input  wire [31:0] d_in,
    input  wire        wmask0,
    output reg  [31:0] d_out,

    input  wire        busy,
    input  wire [31:0] frame_count,

    output reg         enable,
    output reg  [ 9:0] brightness,
    output wire        fb_we,
    output wire [11:0] fb_waddr,
    output wire [ 2:0] fb_wdata
);
    // Escritura del píxel: combinacional, se ejecuta en el flanco del acceso
    assign fb_we    = sel[4] & wmask0;
    assign fb_waddr = addr;
    assign fb_wdata = d_in[2:0];

    always @(posedge clk) begin
        if (rst) begin
            enable     <= 1'b0;
            brightness <= 10'd512;
            d_out      <= 32'd0;
        end else begin
            // Escrituras
            if (sel[0] & wmask0) enable     <= d_in[0];
            if (sel[1] & wmask0) brightness <= d_in[9:0];

            // Lectura registrada
            if (cs & rd) begin
                case (1'b1)
                    sel[0]:  d_out <= {31'd0, enable};
                    sel[1]:  d_out <= {22'd0, brightness};
                    sel[2]:  d_out <= {31'd0, busy};
                    sel[3]:  d_out <= frame_count;
                    default: d_out <= 32'd0;
                endcase
            end
        end
    end
endmodule
