// joystick_uart_tx: transmisor UART 8N1. Envía un byte cuando tx_start vale 1 durante un ciclo:
// bit de inicio (0), 8 bits de datos empezando por el bit 0 y bit de parada (1).
module joystick_uart_tx #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        uart_tx,
    output wire       tx_ocupado
);
    // Mismo divisor que el receptor: 234 ciclos por bit con 27 MHz y 115 200 baudios
    localparam integer CICLOS_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer ANCHO      = (CICLOS_BIT > 1) ? $clog2(CICLOS_BIT) : 1;

    localparam [1:0] REPOSO = 0, INICIO = 1, DATOS = 2, PARADA = 3;

    reg [1:0]       estado;
    reg [ANCHO-1:0] cuenta;
    reg [2:0]       indice;
    reg [7:0]       dato;

    assign tx_ocupado = (estado != REPOSO);

    always @(posedge clk) begin
        if (rst) begin
            estado  <= REPOSO;
            uart_tx <= 1'b1;
            cuenta  <= 0;
            indice  <= 0;
            dato    <= 0;
        end else begin
            case (estado)
                REPOSO: if (tx_start) begin
                    dato    <= tx_data;
                    uart_tx <= 1'b0;                 // bit de inicio
                    cuenta  <= CICLOS_BIT - 1;
                    estado  <= INICIO;
                end

                INICIO: if (cuenta != 0)
                    cuenta <= cuenta - 1'b1;
                else begin
                    uart_tx <= dato[0];              // primer bit de datos
                    indice  <= 0;
                    cuenta  <= CICLOS_BIT - 1;
                    estado  <= DATOS;
                end

                DATOS: if (cuenta != 0)
                    cuenta <= cuenta - 1'b1;
                else if (indice == 3'd7) begin
                    uart_tx <= 1'b1;                 // bit de parada
                    cuenta  <= CICLOS_BIT - 1;
                    estado  <= PARADA;
                end else begin
                    uart_tx <= dato[indice + 3'd1];  // siguiente bit
                    indice  <= indice + 1'b1;
                    cuenta  <= CICLOS_BIT - 1;
                end

                PARADA: if (cuenta != 0)
                    cuenta <= cuenta - 1'b1;
                else
                    estado <= REPOSO;
            endcase
        end
    end
endmodule
