// -----------------------------------------------------------------------------
// DESEMPAQUETADOR (lado receptor) = FSM del diagrama Package_Manager
//
//   S_DIR : espera byte de dirección. Si está en el directorio -> guarda
//           PER_addr y P_Addr y pasa a S_VAL. Si no, lo descarta (dir_err).
//   S_VAL : espera el byte de valor, lo guarda en el registro del periférico
//           y jugador indicados, limpia los latches y vuelve a S_DIR.
//
// Directorio = {PER_X, PER_Y, PER_PUNCH} x {JUG_P1, JUG_P2}  (6 direcciones)
// Los códigos tienen distancia de Hamming >= 2 dentro de cada nibble, así que
// un bit volteado en el byte de dirección nunca produce otra dirección válida.
// Punch: el valor solo puede ser 0x00 o 0x01; otro valor se descarta (val_err).
//
// Los registros de salida solo se limpian con el reset global.
// -----------------------------------------------------------------------------
module desempaquetador #(
    parameter [3:0] PER_X     = 4'h1,
    parameter [3:0] PER_Y     = 4'h2,
    parameter [3:0] PER_PUNCH = 4'h4,
    parameter [3:0] JUG_P1    = 4'h1,
    parameter [3:0] JUG_P2    = 4'h2
)(
    input  wire       clk,
    input  wire       rst_n,
    // Desde la UART
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    // Últimos valores recibidos
    output reg  [7:0] p1_x,
    output reg  [7:0] p1_y,
    output reg        p1_punch,
    output reg  [7:0] p2_x,
    output reg  [7:0] p2_y,
    output reg        p2_punch,
    // Diagnóstico (pulsos de 1 ciclo)
    output reg        dir_err,
    output reg        val_err
);
    localparam S_DIR = 1'b0, S_VAL = 1'b1;

    reg       state;
    reg [3:0] per_l, jug_l;           // PER_addr y P_Addr del paquete en curso

    wire per_ok  = (rx_data[7:4] == PER_X) | (rx_data[7:4] == PER_Y) |
                   (rx_data[7:4] == PER_PUNCH);
    wire jug_ok  = (rx_data[3:0] == JUG_P1) | (rx_data[3:0] == JUG_P2);
    wire addr_ok = per_ok & jug_ok;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_DIR;
            per_l    <= 4'd0;
            jug_l    <= 4'd0;
            p1_x     <= 8'd0;  p1_y <= 8'd0;  p1_punch <= 1'b0;
            p2_x     <= 8'd0;  p2_y <= 8'd0;  p2_punch <= 1'b0;
            dir_err  <= 1'b0;
            val_err  <= 1'b0;
        end else begin
            dir_err <= 1'b0;
            val_err <= 1'b0;

            if (rx_valid) begin
                case (state)
                    S_DIR: begin
                        if (addr_ok) begin
                            per_l <= rx_data[7:4];
                            jug_l <= rx_data[3:0];
                            state <= S_VAL;
                        end else dir_err <= 1'b1;
                    end

                    S_VAL: begin
                        state <= S_DIR;
                        per_l <= 4'd0;        // el reset de la FSM limpia los latches
                        jug_l <= 4'd0;

                        if (per_l == PER_PUNCH && rx_data[7:1] != 7'd0) begin
                            val_err <= 1'b1;  // Punch solo puede valer 0 o 1
                        end else begin
                            if (jug_l == JUG_P1) begin
                                if      (per_l == PER_X)     p1_x     <= rx_data;
                                else if (per_l == PER_Y)     p1_y     <= rx_data;
                                else if (per_l == PER_PUNCH) p1_punch <= rx_data[0];
                            end else if (jug_l == JUG_P2) begin
                                if      (per_l == PER_X)     p2_x     <= rx_data;
                                else if (per_l == PER_Y)     p2_y     <= rx_data;
                                else if (per_l == PER_PUNCH) p2_punch <= rx_data[0];
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule
