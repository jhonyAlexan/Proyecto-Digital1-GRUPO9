`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// G1 - Comunicacion | Unidad de CONTROL del ensamblador de trama (4 bytes)
// Cuenta los bytes de la trama, la descarta si hay error o silencio largo
// (resincronizacion) y ordena publicar los campos cuando llega completa.
// -----------------------------------------------------------------------------
module trama_ctrl (
    input  wire clk,
    input  wire rst_n,
    // Estado del datapath / receptor de bytes
    input  wire byte_listo,     // llego un byte valido
    input  wire error_trama,    // llego un byte con stop invalido
    input  wire timeout,        // silencio > TIMEOUT con trama a medias
    input  wire reservado_ok,   // bits [31:29] de la trama == 0
    // Ordenes al datapath
    output reg  cargar,         // sr <= {sr[23:0], rx_byte}
    output reg  clr_tmo,        // contador de silencio <= 0
    output reg  publicar,       // registros de salida <= campos ; valido = 1
    output reg  [2:0] n_bytes   // bytes recibidos de la trama actual (0..4)
);
    localparam [2:0] B0   = 3'd0,   // esperando byte 3 (MSB)
                     B1   = 3'd1,   // esperando byte 2
                     B2   = 3'd2,   // esperando byte 1
                     B3   = 3'd3,   // esperando byte 0 (LSB)
                     PUB  = 3'd4;   // trama completa: validar y publicar

    reg [2:0] estado, sig;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) estado <= B0;
        else        estado <= sig;

    always @(*) begin
        sig      = estado;
        cargar   = 1'b0;
        clr_tmo  = 1'b0;
        publicar = 1'b0;
        n_bytes  = estado;
        case (estado)
            B0: begin
                clr_tmo = 1'b1;                       // sin trama a medias
                if (byte_listo) begin cargar = 1'b1; sig = B1; end
            end
            B1, B2, B3: begin
                if (error_trama || timeout)  sig = B0;           // descartar
                else if (byte_listo) begin
                    cargar  = 1'b1;
                    clr_tmo = 1'b1;
                    sig     = (estado == B3) ? PUB : estado + 3'd1;
                end
            end
            PUB: begin
                if (reservado_ok) publicar = 1'b1;   // si no, se descarta
                sig = B0;
            end
            default: sig = B0;
        endcase
    end
endmodule
