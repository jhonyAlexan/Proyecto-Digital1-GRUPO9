`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// G1 - Comunicacion | DATAPATH del ensamblador de trama (4 bytes = 32 bits)
// Trama (igual que en las ESP32, se envia MSB primero):
//   [31:29] reservado (0) | [28] ataque | [27:16] Y | [15:4] X | [3:0] ID
// -----------------------------------------------------------------------------
module trama_dp #(
    parameter TIMEOUT = 4680                // 2 bytes UART = 2*10*234 ciclos
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_byte,
    // Ordenes del control
    input  wire        cargar,
    input  wire        clr_tmo,
    input  wire        publicar,
    // Estado hacia el control
    output wire        timeout,
    output wire        reservado_ok,
    // Salidas del modulo
    output reg  [3:0]  id_fpga,
    output reg  [11:0] direccion_x,
    output reg  [11:0] direccion_y,
    output reg         ataque,
    output reg         valido
);
    // Registro de desplazamiento de 32 bits
    reg [31:0] sr;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)      sr <= 32'd0;
        else if (cargar) sr <= {sr[23:0], rx_byte};

    assign reservado_ok = (sr[31:29] == 3'b000);

    // Contador de silencio (resincronizacion de trama)
    reg [12:0] tmo;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)              tmo <= 13'd0;
        else if (clr_tmo)        tmo <= 13'd0;
        else if (tmo != TIMEOUT) tmo <= tmo + 1'b1;
    assign timeout = (tmo == TIMEOUT);

    // Registros de salida (decodificacion CORREGIDA de la trama)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_fpga     <= 4'd0;
            direccion_x <= 12'd0;
            direccion_y <= 12'd0;
            ataque      <= 1'b0;
            valido      <= 1'b0;
        end else begin
            valido <= publicar;
            if (publicar) begin
                id_fpga     <= sr[3:0];
                direccion_x <= sr[15:4];
                direccion_y <= sr[27:16];
                ataque      <= sr[28];
            end
        end
    end
endmodule
