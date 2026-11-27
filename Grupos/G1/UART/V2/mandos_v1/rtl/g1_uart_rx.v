// -----------------------------------------------------------------------------
// g1_uart_rx.v - Receptor UART 8N1 (G1 v1)
//
// Interfaz de salida igual a la del G5 (joystick_uart_rx): rx_data, rx_valid,
// rx_frame_err. Reset sincrono activo en alto (contrato del curso).
// Muestrea a mitad de bit. Incluye sincronizador de 2 flip-flops.
// 27 MHz / 115200 -> 234 ciclos por bit (+0,16 %).
// -----------------------------------------------------------------------------
module g1_uart_rx #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       uart_rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,      // pulso de 1 ciclo: byte listo
    output reg        rx_frame_err   // pulso de 1 ciclo: bit de parada en 0
);
    localparam integer CPB  = CLK_HZ / BAUD;
    localparam integer HALF = CPB / 2;
    localparam integer CW   = $clog2(CPB + 1);

    localparam [2:0] REPOSO = 3'd0, INICIO = 3'd1, DATOS = 3'd2,
                     PARADA = 3'd3, RECUPERAR = 3'd4;

    // Sincronizador (la linea en reposo es 1)
    reg s1, s2;
    always @(posedge clk) begin
        if (rst) begin s1 <= 1'b1; s2 <= 1'b1; end
        else     begin s1 <= uart_rx; s2 <= s1; end
    end

    reg [2:0]    estado;
    reg [CW-1:0] cnt;
    reg [2:0]    nbit;
    reg [7:0]    sh;

    always @(posedge clk) begin
        if (rst) begin
            estado       <= REPOSO;
            cnt          <= 0;
            nbit         <= 3'd0;
            sh           <= 8'd0;
            rx_data      <= 8'd0;
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
        end else begin
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
            case (estado)
                REPOSO: begin
                    cnt  <= 0;
                    nbit <= 3'd0;
                    if (!s2) estado <= INICIO;
                end
                INICIO: begin                       // confirmar a medio bit
                    if (cnt == HALF - 1) begin
                        cnt    <= 0;
                        estado <= s2 ? REPOSO : DATOS;
                    end else cnt <= cnt + 1'b1;
                end
                DATOS: begin
                    if (cnt == CPB - 1) begin
                        cnt <= 0;
                        sh  <= {s2, sh[7:1]};       // LSB primero
                        if (nbit == 3'd7) estado <= PARADA;
                        else              nbit   <= nbit + 1'b1;
                    end else cnt <= cnt + 1'b1;
                end
                PARADA: begin
                    if (cnt == CPB - 1) begin
                        cnt <= 0;
                        if (s2) begin
                            rx_data  <= sh;
                            rx_valid <= 1'b1;
                            estado   <= REPOSO;
                        end else begin
                            rx_frame_err <= 1'b1;
                            estado       <= RECUPERAR;
                        end
                    end else cnt <= cnt + 1'b1;
                end
                RECUPERAR: if (s2) estado <= REPOSO; // esperar linea en alto
                default: estado <= REPOSO;
            endcase
        end
    end
endmodule
