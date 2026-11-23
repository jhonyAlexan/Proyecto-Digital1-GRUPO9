// audio_tiempos: contadores cnt_bclk y cnt_bit, reloj de bit y avisos de tiempo (2.3.3 y 3.3).
// CICLOS_BCLK: ciclos de clk por período de BCLK (16 con 25 MHz, 18 con 27 MHz).
module audio_tiempos #(
    parameter CICLOS_BCLK = 16
) (
    input  wire       clk,
    input  wire       rst,
    output reg        audio_bclk,
    output wire       tick_bajada,
    output reg  [4:0] cnt_bit,
    output wire       carga
);
    localparam ANCHO = $clog2(CICLOS_BCLK);

    reg  [ANCHO-1:0] cnt_bclk;
    wire [ANCHO-1:0] cnt_bclk_sig = tick_bajada ? {ANCHO{1'b0}} : cnt_bclk + 1'b1;

    // El siguiente flanco de clk es el flanco de bajada de BCLK
    assign tick_bajada = (cnt_bclk == CICLOS_BCLK - 1);
    // Fin de trama: se carga una muestra nueva
    assign carga = tick_bajada && (cnt_bit == 5'd31);

    always @(posedge clk) begin
        if (rst) begin
            cnt_bclk   <= {ANCHO{1'b0}};
            cnt_bit    <= 5'd31;
            audio_bclk <= 1'b0;
        end else begin
            cnt_bclk   <= cnt_bclk_sig;
            // BCLK vale 0 en la primera mitad del período y 1 en la segunda
            audio_bclk <= (cnt_bclk_sig >= CICLOS_BCLK / 2);
            if (tick_bajada)
                cnt_bit <= cnt_bit + 1'b1;   // de 31 pasa a 0
        end
    end
endmodule
