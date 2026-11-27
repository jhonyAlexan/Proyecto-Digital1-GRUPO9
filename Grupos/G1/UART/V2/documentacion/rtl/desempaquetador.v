// -----------------------------------------------------------------------------
// DESEMPAQUETADOR (lado receptor, consola) — autor original: Cesar Jaramillo (G1)
// Versión adaptada a la trama acordada con G5 / G6 / G2 (8 bytes):
//
//   byte 0  CABECERA   0xAA
//   byte 1  jugador    1 o 2
//   byte 2  secuencia  0..255 (sube en cada trama)
//   byte 3  X          con signo, -127..127
//   byte 4  Y          con signo, -127..127
//   byte 5  shield     bit 0 (botón del joystick)  -> registro bit 16
//   byte 6  punch      bit 0 (ataque / golpe)      -> registro bit 17
//   byte 7  checksum   XOR de los bytes 1..6
//
// FSM (misma idea del diagrama Package_Manager, ahora por posición):
//   S_DIR : espera la cabecera 0xAA (cualquier otro byte se ignora).
//   S_VAL : guarda los bytes 1..6 en latches mientras acumula el XOR.
//   S_CHK : compara el checksum. Si es correcto y el jugador es 1 o 2,
//           copia TODA la muestra de ese jugador en un solo flanco.
//
// Errores (pulsos de 1 ciclo):
//   dir_err : trama completa con checksum bien pero jugador distinto de 1 y 2
//   val_err : checksum incorrecto (la muestra se descarta)
// Resincronización: si llega rx_frame_err o pasan T_MAX_CICLOS sin bytes con
// una trama a medias, se descarta y se vuelve a S_DIR.
//
// Los registros de salida solo se limpian con el reset global.
// -----------------------------------------------------------------------------
module desempaquetador #(
    parameter [7:0]  CABECERA     = 8'hAA,
    parameter [7:0]  JUG_P1       = 8'd1,
    parameter [7:0]  JUG_P2       = 8'd2,
    parameter integer T_MAX_CICLOS = 27_000          // 1 ms a 27 MHz
)(
    input  wire       clk,
    input  wire       rst_n,
    // Desde la UART
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       rx_frame_err,
    // Última muestra válida de cada jugador
    output reg  [7:0] p1_x,
    output reg  [7:0] p1_y,
    output reg        p1_punch,
    output reg        p1_shield,
    output reg  [7:0] p1_seq,
    output reg  [7:0] p2_x,
    output reg  [7:0] p2_y,
    output reg        p2_punch,
    output reg        p2_shield,
    output reg  [7:0] p2_seq,
    // Pulsos de 1 ciclo
    output reg        p1_nuevo,     // llegó una trama válida del jugador 1
    output reg        p2_nuevo,     // llegó una trama válida del jugador 2
    output reg        dir_err,
    output reg        val_err
);
    localparam [1:0] S_DIR = 2'd0, S_VAL = 2'd1, S_CHK = 2'd2;
    localparam integer TW = $clog2(T_MAX_CICLOS + 1);

    reg [1:0]    state;
    reg [2:0]    idx;                       // byte esperado dentro de S_VAL (1..6)
    reg [7:0]    jug_l, seq_l, x_l, y_l;    // latches de la trama en curso
    reg          shield_l, punch_l;
    reg [7:0]    xor_l;
    reg [TW-1:0] espera;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_DIR;
            idx      <= 3'd0;
            jug_l    <= 8'd0;  seq_l <= 8'd0;  x_l <= 8'd0;  y_l <= 8'd0;
            shield_l <= 1'b0;  punch_l <= 1'b0;
            xor_l    <= 8'd0;
            espera   <= 0;
            p1_x <= 8'd0; p1_y <= 8'd0; p1_punch <= 1'b0; p1_shield <= 1'b0; p1_seq <= 8'd0;
            p2_x <= 8'd0; p2_y <= 8'd0; p2_punch <= 1'b0; p2_shield <= 1'b0; p2_seq <= 8'd0;
            p1_nuevo <= 1'b0;  p2_nuevo <= 1'b0;
            dir_err  <= 1'b0;  val_err  <= 1'b0;
        end else begin
            p1_nuevo <= 1'b0;  p2_nuevo <= 1'b0;
            dir_err  <= 1'b0;  val_err  <= 1'b0;

            if (rx_frame_err) begin                 // byte corrupto: descartar trama
                state  <= S_DIR;
                espera <= 0;
            end else if (rx_valid) begin
                espera <= 0;
                case (state)
                    S_DIR: if (rx_data == CABECERA) begin
                        idx   <= 3'd1;
                        xor_l <= 8'd0;
                        state <= S_VAL;
                    end

                    S_VAL: begin
                        xor_l <= xor_l ^ rx_data;
                        case (idx)
                            3'd1:    jug_l    <= rx_data;
                            3'd2:    seq_l    <= rx_data;
                            3'd3:    x_l      <= rx_data;
                            3'd4:    y_l      <= rx_data;
                            3'd5:    shield_l <= rx_data[0];
                            default: punch_l  <= rx_data[0];
                        endcase
                        if (idx == 3'd6) state <= S_CHK;
                        else             idx   <= idx + 1'b1;
                    end

                    S_CHK: begin
                        state <= S_DIR;
                        if (rx_data != xor_l) begin
                            val_err <= 1'b1;        // checksum malo: se conserva lo anterior
                        end else if (jug_l == JUG_P1) begin
                            p1_x <= x_l; p1_y <= y_l; p1_shield <= shield_l;
                            p1_punch <= punch_l; p1_seq <= seq_l;
                            p1_nuevo <= 1'b1;
                        end else if (jug_l == JUG_P2) begin
                            p2_x <= x_l; p2_y <= y_l; p2_shield <= shield_l;
                            p2_punch <= punch_l; p2_seq <= seq_l;
                            p2_nuevo <= 1'b1;
                        end else begin
                            dir_err <= 1'b1;        // jugador que no existe
                        end
                    end

                    default: state <= S_DIR;
                endcase
            end else if (state != S_DIR) begin      // plazo entre bytes
                if (espera == T_MAX_CICLOS - 1) begin
                    state  <= S_DIR;
                    espera <= 0;
                end else espera <= espera + 1'b1;
            end
        end
    end
endmodule
