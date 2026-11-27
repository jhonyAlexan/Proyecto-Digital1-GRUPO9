// -----------------------------------------------------------------------------
// perip_mandos.v — Periférico de mandos para el SoC de la consola (G1)
// Usa uart_8n1 + desempaquetador (Cesar Jaramillo) y presenta los registros
// que espera el juego del G6 (firmware/hardware.h) y que documenta el G5.
//
// Región del SoC: 0x0047_xxxx  (chip_select.v, cs[7])
//   +0x0  JOY1_DATA  [7:0] X  [15:8] Y  [16] shield (botón)  [17] punch (ataque)
//                    [23:18] 0  [31:24] secuencia
//   +0x4  JOY2_DATA  igual para el jugador 2
//   +0x8  STATUS     [0] P1_VALID  [1] P2_VALID  [2] UART_ERROR  [3] CHECKSUM_ERROR
//   otros 0
// Las banderas de STATUS quedan en 1 hasta el reset (contrato del G5).
//
// Bus igual al de peripheral_mult / peripheral_uart del SoC:
//   clk, reset (alto), d_in, cs, addr[31:0] (solo addr[3:0]), rd, wr, d_out
//   d_out se captura en el flanco siguiente a cs & rd (misma latencia que mult).
// Registros de solo lectura: wr y d_in no se usan.
// -----------------------------------------------------------------------------
module peripheral_mandos #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] d_in,
    input  wire        cs,
    input  wire [31:0] addr,
    input  wire        rd,
    input  wire        wr,
    output reg  [31:0] d_out,
    // Línea física: TX de la ESP32 de la consola
    input  wire        uart_rx,
    // Para LEDs o depuración (opcional)
    output wire [31:0] joy1_data,
    output wire [31:0] joy2_data,
    output wire [3:0]  status
);
    wire rst_n = ~reset;

    // ---------------- UART (solo RX) ----------------
    wire [7:0] rx_data;
    wire       rx_valid, rx_frame_err;

    uart_8n1 #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .tx_data(8'd0), .tx_start(1'b0), .tx(), .tx_busy(),
        .rx(uart_rx), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_frame_err(rx_frame_err));

    // ---------------- Desempaquetador ----------------
    wire [7:0] p1_x, p1_y, p1_seq, p2_x, p2_y, p2_seq;
    wire       p1_punch, p1_shield, p2_punch, p2_shield;
    wire       p1_nuevo, p2_nuevo, dir_err, val_err;

    desempaquetador #(.T_MAX_CICLOS(CLK_HZ / 1000)) des (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .p1_x(p1_x), .p1_y(p1_y), .p1_punch(p1_punch), .p1_shield(p1_shield), .p1_seq(p1_seq),
        .p2_x(p2_x), .p2_y(p2_y), .p2_punch(p2_punch), .p2_shield(p2_shield), .p2_seq(p2_seq),
        .p1_nuevo(p1_nuevo), .p2_nuevo(p2_nuevo),
        .dir_err(dir_err), .val_err(val_err));

    // ---------------- STATUS ----------------
    reg p1_valid, p2_valid, uart_error, chk_error;
    always @(posedge clk) begin
        if (reset) begin
            p1_valid <= 1'b0;  p2_valid  <= 1'b0;
            uart_error <= 1'b0; chk_error <= 1'b0;
        end else begin
            if (p1_nuevo)     p1_valid   <= 1'b1;
            if (p2_nuevo)     p2_valid   <= 1'b1;
            if (rx_frame_err) uart_error <= 1'b1;
            if (val_err)      chk_error  <= 1'b1;
        end
    end

    assign joy1_data = {p1_seq, 6'd0, p1_punch, p1_shield, p1_y, p1_x};
    assign joy2_data = {p2_seq, 6'd0, p2_punch, p2_shield, p2_y, p2_x};
    assign status    = {chk_error, uart_error, p2_valid, p1_valid};

    // ---------------- Lectura desde el procesador ----------------
    always @(posedge clk) begin
        if (reset) d_out <= 32'd0;
        else if (cs && rd) begin
            case (addr[3:0])
                4'h0:    d_out <= joy1_data;
                4'h4:    d_out <= joy2_data;
                4'h8:    d_out <= {28'd0, status};
                default: d_out <= 32'd0;
            endcase
        end
    end

    wire _sin_uso = &{1'b0, wr, d_in, addr[31:4]};
endmodule
