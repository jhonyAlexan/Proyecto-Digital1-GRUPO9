// -----------------------------------------------------------------------------
// g1_trama_rx.v - Ensamblador y validador de la trama de 8 bytes (G1 v1)
//
//   [0] 0xAA  [1] jugador  [2] secuencia  [3] X  [4] Y  [5] boton  [6] ataque
//   [7] XOR de los bytes 1 a 6
//
// datos_muestra sigue el mapa del registro JOYn_DATA (G5 3.2.5, G6 hardware.h):
//   [7:0] X  [15:8] Y  [16] boton  [17] ataque  [23:18] 0  [31:24] secuencia
//
// Un 0xAA dentro de los campos se trata como dato (se cuenta por posicion).
// Si pasan T_MAX_CICLOS sin byte con una trama a medias, se descarta y se
// vuelve a buscar 0xAA (resincronizacion). Un error de trama UART tambien
// descarta la trama en curso.
// -----------------------------------------------------------------------------
module g1_trama_rx #(
    parameter integer CLK_HZ       = 27_000_000,
    parameter integer T_MAX_CICLOS = CLK_HZ / 1000      // 1 ms entre bytes
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_frame_err,
    output reg  [31:0] datos_muestra,
    output reg         cargar_p1,       // pulso: trama valida del jugador 1
    output reg         cargar_p2,       // pulso: trama valida del jugador 2
    output reg         checksum_error   // pulso: XOR incorrecto
);
    localparam [1:0] BUSCAR = 2'd0, CAMPOS = 2'd1, CHECKSUM = 2'd2;
    localparam integer TW = $clog2(T_MAX_CICLOS + 1);

    reg [1:0]    estado;
    reg [2:0]    indice;                 // byte que se espera (1..6)
    reg [7:0]    jugador, secuencia, eje_x, eje_y;
    reg          boton, ataque;
    reg [7:0]    xor_acc;
    reg [TW-1:0] espera;

    always @(posedge clk) begin
        if (rst) begin
            estado         <= BUSCAR;
            indice         <= 3'd0;
            jugador        <= 8'd0;
            secuencia      <= 8'd0;
            eje_x          <= 8'd0;
            eje_y          <= 8'd0;
            boton          <= 1'b0;
            ataque         <= 1'b0;
            xor_acc        <= 8'd0;
            espera         <= 0;
            datos_muestra  <= 32'd0;
            cargar_p1      <= 1'b0;
            cargar_p2      <= 1'b0;
            checksum_error <= 1'b0;
        end else begin
            cargar_p1      <= 1'b0;
            cargar_p2      <= 1'b0;
            checksum_error <= 1'b0;

            if (rx_frame_err) begin
                estado <= BUSCAR;
                espera <= 0;
            end else if (rx_valid) begin
                espera <= 0;
                case (estado)
                    BUSCAR: if (rx_data == 8'hAA) begin
                        indice  <= 3'd1;
                        xor_acc <= 8'd0;
                        estado  <= CAMPOS;
                    end
                    CAMPOS: begin
                        xor_acc <= xor_acc ^ rx_data;
                        case (indice)
                            3'd1: jugador   <= rx_data;
                            3'd2: secuencia <= rx_data;
                            3'd3: eje_x     <= rx_data;
                            3'd4: eje_y     <= rx_data;
                            3'd5: boton     <= rx_data[0];
                            default: ataque <= rx_data[0];
                        endcase
                        if (indice == 3'd6) estado <= CHECKSUM;
                        else                indice <= indice + 1'b1;
                    end
                    CHECKSUM: begin
                        estado <= BUSCAR;
                        if (rx_data != xor_acc) begin
                            checksum_error <= 1'b1;
                        end else if (jugador == 8'd1 || jugador == 8'd2) begin
                            datos_muestra <= {secuencia, 6'd0, ataque, boton, eje_y, eje_x};
                            cargar_p1     <= (jugador == 8'd1);
                            cargar_p2     <= (jugador == 8'd2);
                        end
                        // jugador invalido con XOR correcto: se descarta sin bandera
                    end
                    default: estado <= BUSCAR;
                endcase
            end else if (estado != BUSCAR) begin
                if (espera == T_MAX_CICLOS - 1) begin
                    estado <= BUSCAR;           // trama incompleta: descartar
                    espera <= 0;
                end else espera <= espera + 1'b1;
            end
        end
    end
endmodule
