// joystick_solicitud: la FPGA es la maestra. Cada PERIODO_CICLOS le pide una lectura a la ESP32
// enviando el byte SOLICITUD ('?', 0x3F). Si pasan MAX_SIN_RESPUESTA solicitudes seguidas sin un
// paquete válido, comunicacion_ok baja a 0.
module joystick_solicitud #(
    parameter integer PERIODO_CICLOS    = 270_000,   // 10 ms a 27 MHz: 100 lecturas por segundo
    parameter integer MAX_SIN_RESPUESTA = 10,        // 10 solicitudes = 100 ms sin respuesta
    parameter [7:0]   SOLICITUD         = 8'h3F      // '?'
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_ocupado,        // el transmisor todavía envía el byte anterior
    input  wire       respuesta_valida,  // llegó un paquete con XOR correcto
    output reg        tx_start,
    output wire [7:0] tx_data,
    output reg        comunicacion_ok
);
    localparam integer ANCHO = (PERIODO_CICLOS > 1) ? $clog2(PERIODO_CICLOS) : 1;

    reg [ANCHO-1:0] cuenta;
    reg [7:0]       sin_respuesta;

    assign tx_data = SOLICITUD;

    always @(posedge clk) begin
        if (rst) begin
            cuenta          <= 0;
            sin_respuesta   <= 0;
            tx_start        <= 1'b0;
            comunicacion_ok <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            // Temporizador de la solicitud
            if (cuenta == PERIODO_CICLOS - 1) begin
                cuenta <= 0;
                if (!tx_ocupado)
                    tx_start <= 1'b1;
                if (sin_respuesta == MAX_SIN_RESPUESTA)
                    comunicacion_ok <= 1'b0;
                else
                    sin_respuesta <= sin_respuesta + 1'b1;
            end else begin
                cuenta <= cuenta + 1'b1;
            end

            // Un paquete válido reinicia la cuenta de solicitudes sin respuesta
            if (respuesta_valida) begin
                sin_respuesta   <= 0;
                comunicacion_ok <= 1'b1;
            end
        end
    end
endmodule
