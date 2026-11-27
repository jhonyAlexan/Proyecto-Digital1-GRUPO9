// -----------------------------------------------------------------------------
// EMPAQUETADOR (lado emisor de un mando) — autor original: Cesar Jaramillo (G1)
// Versión adaptada a la trama acordada con G5 / G6 / G2 (8 bytes):
//
//   byte 0  CABECERA   0xAA
//   byte 1  jugador    1 o 2
//   byte 2  secuencia  sube en cada trama (la lleva este módulo)
//   byte 3  X          con signo, -127..127
//   byte 4  Y          con signo, -127..127
//   byte 5  shield     {7'b0, shield}   (botón del joystick)
//   byte 6  punch      {7'b0, punch}    (ataque / golpe)
//   byte 7  checksum   XOR de los bytes 1..6
//
// Cada PERIODO ciclos (por defecto 1/30 s) congela la muestra del mando y
// manda los 8 bytes seguidos. Como se manda siempre, si una trama se pierde
// la siguiente corrige al receptor.
//
// FSM:  S_SCAN  -> espera el periodo y congela x, y, shield, punch
//       S_ADDR  -> pone el byte idx en la UART (antes: byte de dirección)
//       S_ADDR_W-> espera a que la UART termine; idx+1 o vuelve a S_SCAN
// -----------------------------------------------------------------------------
module empaquetador #(
    parameter [7:0]   CABECERA = 8'hAA,
    parameter integer CLK_HZ   = 27_000_000,
    parameter integer TASA_HZ  = 30,                   // tramas por segundo
    parameter integer PERIODO  = CLK_HZ / TASA_HZ      // ciclos entre tramas
)(
    input  wire       clk,
    input  wire       rst_n,
    // Mando
    input  wire [3:0] jugador,        // 4'h1 = P1, 4'h2 = P2
    input  wire [7:0] x,              // con signo
    input  wire [7:0] y,              // con signo
    input  wire       punch,
    input  wire       shield,
    // Hacia la UART
    output reg  [7:0] tx_data,
    output reg        tx_start,
    input  wire       tx_busy
);
    localparam [1:0] S_SCAN = 2'd0, S_ADDR = 2'd1, S_ADDR_W = 2'd2;
    localparam integer PW = $clog2(PERIODO + 1);

    reg [1:0]    state;
    reg [2:0]    idx;                 // byte de la trama que se está mandando (0..7)
    reg [PW-1:0] cnt;                 // contador del periodo
    reg [7:0]    seq;                 // número de secuencia
    reg [7:0]    jug_l, x_l, y_l;     // muestra congelada para la trama en curso
    reg          shield_l, punch_l;

    wire [7:0] chk = jug_l ^ seq ^ x_l ^ y_l ^ {7'b0, shield_l} ^ {7'b0, punch_l};

    reg [7:0] cur;                    // byte idx de la trama
    always @(*) begin
        case (idx)
            3'd0:    cur = CABECERA;
            3'd1:    cur = jug_l;
            3'd2:    cur = seq;
            3'd3:    cur = x_l;
            3'd4:    cur = y_l;
            3'd5:    cur = {7'b0, shield_l};
            3'd6:    cur = {7'b0, punch_l};
            default: cur = chk;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_SCAN;
            idx      <= 3'd0;
            cnt      <= 0;
            seq      <= 8'd0;
            jug_l    <= 8'd0;  x_l <= 8'd0;  y_l <= 8'd0;
            shield_l <= 1'b0;  punch_l <= 1'b0;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (cnt != 0) cnt <= cnt - 1'b1;

            case (state)
                S_SCAN: if (cnt == 0) begin            // tras reset sale de una vez
                    cnt      <= PERIODO - 1;
                    jug_l    <= {4'h0, jugador};
                    x_l      <= x;
                    y_l      <= y;
                    shield_l <= shield;
                    punch_l  <= punch;
                    idx      <= 3'd0;
                    state    <= S_ADDR;
                end
                S_ADDR: if (!tx_busy) begin
                    tx_data  <= cur;
                    tx_start <= 1'b1;
                    state    <= S_ADDR_W;
                end
                S_ADDR_W: if (!tx_busy) begin
                    if (idx == 3'd7) begin
                        seq   <= seq + 1'b1;
                        state <= S_SCAN;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_ADDR;
                    end
                end
                default: state <= S_SCAN;
            endcase
        end
    end
endmodule
