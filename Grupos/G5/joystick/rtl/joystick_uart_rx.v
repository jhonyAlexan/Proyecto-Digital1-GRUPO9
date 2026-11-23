module joystick_uart_rx #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       uart_rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_frame_err
);
    // Divisor redondeado al entero más cercano. Requiere al menos 2 ciclos/bit.
    localparam integer CICLOS_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer MEDIO_BIT  = CICLOS_BIT / 2;
    localparam integer ANCHO      = (CICLOS_BIT > 1) ? $clog2(CICLOS_BIT) : 1;

    localparam [2:0] REPOSO = 0, INICIO = 1, DATOS = 2,
                     PARADA = 3, RECUPERAR = 4;

    wire rx_sync;
    reg [2:0] estado;
    reg [ANCHO-1:0] cuenta;
    reg [2:0] indice;
    reg [7:0] muestra;

    joystick_rx_sync sincronizador (
        .clk(clk), .rst(rst), .uart_rx(uart_rx), .rx_sync(rx_sync)
    );

    always @(posedge clk) begin
        if (rst) begin
            estado       <= REPOSO;
            cuenta       <= 0;
            indice       <= 0;
            muestra      <= 0;
            rx_data      <= 0;
            rx_valid     <= 0;
            rx_frame_err <= 0;
        end else begin
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;

            if (cuenta != 0) begin
                cuenta <= cuenta - 1'b1;
            end else begin
                case (estado)
                    REPOSO: if (!rx_sync) begin
                        cuenta <= MEDIO_BIT - 1;
                        estado <= INICIO;
                    end

                    INICIO: if (!rx_sync) begin
                        indice <= 0;
                        cuenta <= CICLOS_BIT - 1;
                        estado <= DATOS;
                    end else begin
                        estado <= REPOSO;
                    end

                    DATOS: begin
                        muestra[indice] <= rx_sync;
                        cuenta <= CICLOS_BIT - 1;
                        if (indice == 3'd7)
                            estado <= PARADA;
                        else
                            indice <= indice + 1'b1;
                    end

                    PARADA: if (rx_sync) begin
                        rx_data  <= muestra;
                        rx_valid <= 1'b1;
                        estado   <= REPOSO;
                    end else begin
                        rx_frame_err <= 1'b1;
                        estado       <= RECUPERAR;
                    end

                    RECUPERAR: if (rx_sync)
                        estado <= REPOSO;

                    default: estado <= REPOSO;
                endcase
            end
        end
    end
endmodule
