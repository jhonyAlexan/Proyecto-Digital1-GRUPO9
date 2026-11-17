// -----------------------------------------------------------------------------
// EMPAQUETADOR (lado emisor de un mando)
//
// Recorre los 3 periféricos (X, Y, Punch) y por cada uno manda 2 bytes:
//     byte 1: {PER_addr[3:0], jugador[3:0]}
//     byte 2: valor  (Punch -> {7'b0, punch})
//
// SOLO_CAMBIOS = 0 : manda todo continuamente (se autocorrige si algo se pierde)
// SOLO_CAMBIOS = 1 : manda un periférico solo si cambió (más liviano, pero si se
//                    pierde un paquete el receptor queda con el valor viejo)
// Tras un reset siempre se manda cada periférico al menos una vez.
// -----------------------------------------------------------------------------
module empaquetador #(
    parameter [3:0] PER_X     = 4'h1,
    parameter [3:0] PER_Y     = 4'h2,
    parameter [3:0] PER_PUNCH = 4'h4,
    parameter       SOLO_CAMBIOS = 0
)(
    input  wire       clk,
    input  wire       rst_n,
    // Mando
    input  wire [3:0] jugador,        // 4'h1 = P1, 4'h2 = P2
    input  wire [7:0] x,
    input  wire [7:0] y,
    input  wire       punch,
    // Hacia la UART
    output reg  [7:0] tx_data,
    output reg        tx_start,
    input  wire       tx_busy
);
    localparam S_SCAN = 3'd0, S_ADDR = 3'd1, S_ADDR_W = 3'd2,
               S_VAL  = 3'd3, S_VAL_W = 3'd4;

    reg [2:0]  state;
    reg [1:0]  idx;                   // 0 = X, 1 = Y, 2 = Punch
    reg [7:0]  val_l;                 // valor congelado para el paquete en curso
    reg [23:0] last;                  // último valor enviado de cada periférico
    reg [2:0]  pend;                  // pendiente de primer envío tras reset

    wire [7:0] cur = (idx == 2'd0) ? x :
                     (idx == 2'd1) ? y : {7'b0, punch};
    wire [3:0] per = (idx == 2'd0) ? PER_X :
                     (idx == 2'd1) ? PER_Y : PER_PUNCH;

    wire cambio  = (cur != last[idx*8 +: 8]) | pend[idx];
    wire enviar  = (SOLO_CAMBIOS == 0) | cambio;
    wire [1:0] idx_sig = (idx == 2'd2) ? 2'd0 : idx + 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_SCAN;
            idx      <= 2'd0;
            val_l    <= 8'd0;
            last     <= 24'd0;
            pend     <= 3'b111;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            case (state)
                S_SCAN: begin
                    if (enviar) begin
                        val_l              <= cur;
                        last[idx*8 +: 8]   <= cur;
                        pend[idx]          <= 1'b0;
                        state              <= S_ADDR;
                    end else idx <= idx_sig;
                end
                S_ADDR: if (!tx_busy) begin
                    tx_data  <= {per, jugador};
                    tx_start <= 1'b1;
                    state    <= S_ADDR_W;
                end
                S_ADDR_W: if (!tx_busy) state <= S_VAL;
                S_VAL: if (!tx_busy) begin
                    tx_data  <= val_l;
                    tx_start <= 1'b1;
                    state    <= S_VAL_W;
                end
                S_VAL_W: if (!tx_busy) begin
                    idx   <= idx_sig;
                    state <= S_SCAN;
                end
                default: state <= S_SCAN;
            endcase
        end
    end
endmodule
