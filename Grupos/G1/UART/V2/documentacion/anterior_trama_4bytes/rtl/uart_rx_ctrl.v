`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// G1 - Comunicacion | Unidad de CONTROL del receptor UART 8N1 (un byte)
// FSM Moore/Mealy de 4 estados. Solo decide; no guarda datos.
// Ver documentacion/README.md (V2), etapas 6 (ASMD) y 8 (FSM).
// -----------------------------------------------------------------------------
module uart_rx_ctrl (
    input  wire clk,
    input  wire rst_n,
    // Estado del datapath
    input  wire rx_in,        // linea RX ya sincronizada
    input  wire medio_bit,    // contador == (CLKS_PER_BIT-1)/2
    input  wire fin_bit,      // contador == CLKS_PER_BIT-1
    input  wire ultimo_bit,   // indice de bit == 7
    // Ordenes al datapath
    output reg  clr_cnt,      // contador de ciclos <= 0
    output reg  clr_idx,      // indice de bit <= 0
    output reg  desplazar,    // rx_byte <= {rx_in, rx_byte[7:1]} ; idx++
    output reg  byte_listo,   // pulso: byte recibido con stop correcto
    output reg  error_trama   // pulso: stop = 0 (framing error)
);
    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0] estado, sig;

    // Registro de estado
    always @(posedge clk or negedge rst_n)
        if (!rst_n) estado <= IDLE;
        else        estado <= sig;

    // Logica de siguiente estado y salidas (combinacional)
    always @(*) begin
        sig         = estado;
        clr_cnt     = 1'b0;
        clr_idx     = 1'b0;
        desplazar   = 1'b0;
        byte_listo  = 1'b0;
        error_trama = 1'b0;
        case (estado)
            IDLE: begin
                clr_cnt = 1'b1;
                clr_idx = 1'b1;
                if (!rx_in) sig = START;              // flanco de bajada
            end
            START: begin
                if (medio_bit) begin
                    clr_cnt = 1'b1;                   // re-centrar en mitad de bit
                    sig     = rx_in ? IDLE : DATA;    // glitch -> vuelve a IDLE
                end
            end
            DATA: begin
                if (fin_bit) begin
                    clr_cnt   = 1'b1;
                    desplazar = 1'b1;                 // muestra en la mitad del bit
                    if (ultimo_bit) sig = STOP;
                end
            end
            STOP: begin
                if (fin_bit) begin
                    clr_cnt = 1'b1;
                    if (rx_in) byte_listo  = 1'b1;    // stop valido
                    else       error_trama = 1'b1;    // stop invalido
                    sig = IDLE;
                end
            end
        endcase
    end
endmodule
