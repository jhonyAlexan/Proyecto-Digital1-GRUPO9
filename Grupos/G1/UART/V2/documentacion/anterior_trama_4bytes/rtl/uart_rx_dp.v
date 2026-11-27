`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// G1 - Comunicacion | DATAPATH del receptor UART 8N1 (un byte)
// Sincronizador, contador de ciclos por bit, indice de bit y registro de
// desplazamiento. Solo ejecuta las ordenes de uart_rx_ctrl.
// -----------------------------------------------------------------------------
module uart_rx_dp #(
    parameter CLKS_PER_BIT = 234            // 27 MHz / 115200 = 234,375
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,              // pin fisico (asincrono)
    // Ordenes del control
    input  wire       clr_cnt,
    input  wire       clr_idx,
    input  wire       desplazar,
    // Estado hacia el control
    output wire       rx_in,
    output wire       medio_bit,
    output wire       fin_bit,
    output wire       ultimo_bit,
    // Dato
    output reg  [7:0] rx_byte
);
    // Sincronizador de 2 flip-flops (metaestabilidad)
    reg [1:0] rx_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rx_sync <= 2'b11;
        else        rx_sync <= {rx_sync[0], uart_rx};
    assign rx_in = rx_sync[1];

    // Contador de ciclos dentro de un bit
    reg [7:0] cnt;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)       cnt <= 8'd0;
        else if (clr_cnt) cnt <= 8'd0;
        else              cnt <= cnt + 1'b1;

    assign medio_bit = (cnt == (CLKS_PER_BIT-1)/2);   // 116
    assign fin_bit   = (cnt == CLKS_PER_BIT-1);       // 233

    // Indice de bit (0..7)
    reg [2:0] idx;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)         idx <= 3'd0;
        else if (clr_idx)   idx <= 3'd0;
        else if (desplazar) idx <= idx + 1'b1;
    assign ultimo_bit = (idx == 3'd7);

    // Registro de desplazamiento: UART envia LSB primero
    always @(posedge clk or negedge rst_n)
        if (!rst_n)         rx_byte <= 8'd0;
        else if (desplazar) rx_byte <= {rx_in, rx_byte[7:1]};
endmodule
