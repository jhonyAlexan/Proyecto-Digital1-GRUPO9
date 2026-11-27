`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// G1 - Comunicacion | TOP del receptor UART de trama de 32 bits
// Tang Nano 9K @ 27 MHz, 115200 baudios 8N1.
// Mismos puertos que Control/fpga1_uart_rx.v, para poder reemplazarlo.
// La FPGA #2 (Consola) usa este mismo modulo; reg_* = estas salidas.
//
//  uart_rx --> [uart_rx_dp <-> uart_rx_ctrl] --rx_byte/byte_listo-->
//              [trama_dp   <-> trama_ctrl  ] --> id, x, y, ataque, valido
// -----------------------------------------------------------------------------
module uart_rx_g1 #(
    parameter CLKS_PER_BIT = 234,
    parameter TIMEOUT      = 2*10*CLKS_PER_BIT
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire [3:0]  id_fpga,
    output wire [11:0] direccion_x,
    output wire [11:0] direccion_y,
    output wire        ataque,
    output wire        valido
);
    // Interconexion receptor de bytes
    wire rx_in, medio_bit, fin_bit, ultimo_bit;
    wire clr_cnt, clr_idx, desplazar, byte_listo, error_trama;
    wire [7:0] rx_byte;

    uart_rx_dp #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx_dp (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
        .clr_cnt(clr_cnt), .clr_idx(clr_idx), .desplazar(desplazar),
        .rx_in(rx_in), .medio_bit(medio_bit), .fin_bit(fin_bit),
        .ultimo_bit(ultimo_bit), .rx_byte(rx_byte)
    );

    uart_rx_ctrl u_rx_ctrl (
        .clk(clk), .rst_n(rst_n),
        .rx_in(rx_in), .medio_bit(medio_bit), .fin_bit(fin_bit),
        .ultimo_bit(ultimo_bit),
        .clr_cnt(clr_cnt), .clr_idx(clr_idx), .desplazar(desplazar),
        .byte_listo(byte_listo), .error_trama(error_trama)
    );

    // Interconexion ensamblador de trama
    wire cargar, clr_tmo, publicar, timeout, reservado_ok;
    wire [2:0] n_bytes;

    trama_ctrl u_tr_ctrl (
        .clk(clk), .rst_n(rst_n),
        .byte_listo(byte_listo), .error_trama(error_trama),
        .timeout(timeout), .reservado_ok(reservado_ok),
        .cargar(cargar), .clr_tmo(clr_tmo), .publicar(publicar),
        .n_bytes(n_bytes)
    );

    trama_dp #(.TIMEOUT(TIMEOUT)) u_tr_dp (
        .clk(clk), .rst_n(rst_n), .rx_byte(rx_byte),
        .cargar(cargar), .clr_tmo(clr_tmo), .publicar(publicar),
        .timeout(timeout), .reservado_ok(reservado_ok),
        .id_fpga(id_fpga), .direccion_x(direccion_x),
        .direccion_y(direccion_y), .ataque(ataque), .valido(valido)
    );
endmodule
