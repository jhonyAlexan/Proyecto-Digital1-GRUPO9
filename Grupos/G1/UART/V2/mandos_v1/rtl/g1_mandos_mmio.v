// -----------------------------------------------------------------------------
// g1_mandos_mmio.v - Periferico de mandos para el SoC (G1 v1)
//
// Mismo mapa que espera el juego del G6 (firmware/hardware.h) y que documenta
// el G5 (joystick README 3.2.5). Region propuesta: 0x0047_xxxx.
//
//   addr 0x0  JOY1_DATA  [7:0] X  [15:8] Y  [16] boton  [17] ataque  [31:24] secuencia
//   addr 0x4  JOY2_DATA  igual para el jugador 2
//   addr 0x8  STATUS     [0] P1_VALID  [1] P2_VALID  [2] UART_ERROR  [3] CHECKSUM_ERROR
//   otros     0
//
// Bus del curso: clk, rst (sincrono, alto), cs, rd, wr, addr[3:0] (bytes),
// d_in, d_out (registrado), ack (= cs del ciclo anterior).
// Los registros son de solo lectura; las banderas quedan hasta rst.
// La muestra de cada jugador se escribe completa en un solo flanco.
// -----------------------------------------------------------------------------
module g1_mandos_mmio #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        cs,
    input  wire        rd,
    input  wire        wr,
    input  wire [3:0]  addr,
    input  wire [31:0] d_in,
    output reg  [31:0] d_out,
    output reg         ack,
    // Enlace fisico: TX de la ESP32 de la consola (GPIO17)
    input  wire        uart_rx,
    // Para LEDs o depuracion (opcional)
    output wire [31:0] joy1_data,
    output wire [31:0] joy2_data,
    output wire [3:0]  status,
    output wire        trama_ok          // pulso por cada trama valida
);
    wire [7:0]  rx_data;
    wire        rx_valid, rx_frame_err;
    wire [31:0] muestra;
    wire        cargar_p1, cargar_p2, checksum_error;

    g1_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .uart_rx(uart_rx),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err));

    g1_trama_rx #(.CLK_HZ(CLK_HZ)) u_trama (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .datos_muestra(muestra), .cargar_p1(cargar_p1), .cargar_p2(cargar_p2),
        .checksum_error(checksum_error));

    // ---------------- Banco de registros ----------------
    reg [31:0] joy1, joy2;
    reg        p1_valid, p2_valid, uart_error, chk_error;

    always @(posedge clk) begin
        if (rst) begin
            joy1 <= 32'd0;  joy2 <= 32'd0;
            p1_valid <= 1'b0;  p2_valid <= 1'b0;
            uart_error <= 1'b0;  chk_error <= 1'b0;
        end else begin
            if (cargar_p1) begin joy1 <= muestra; p1_valid <= 1'b1; end
            if (cargar_p2) begin joy2 <= muestra; p2_valid <= 1'b1; end
            if (rx_frame_err)   uart_error <= 1'b1;
            if (checksum_error) chk_error  <= 1'b1;
        end
    end

    assign joy1_data = joy1;
    assign joy2_data = joy2;
    assign status    = {chk_error, uart_error, p2_valid, p1_valid};
    assign trama_ok  = cargar_p1 | cargar_p2;

    // ---------------- Interfaz con el bus ----------------
    always @(posedge clk) begin
        if (rst) begin
            d_out <= 32'd0;
            ack   <= 1'b0;
        end else begin
            ack <= cs;
            if (cs && rd) begin
                case (addr)
                    4'h0:    d_out <= joy1;
                    4'h4:    d_out <= joy2;
                    4'h8:    d_out <= {28'd0, status};
                    default: d_out <= 32'd0;
                endcase
            end
        end
    end

    // wr y d_in no se usan: registros de solo lectura
    wire _sin_uso = &{1'b0, wr, d_in};
endmodule
