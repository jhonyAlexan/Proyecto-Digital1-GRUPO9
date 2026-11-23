// audio_nco: acumulador de fase de 16 bits y muestra de onda cuadrada (1.2 y 3.3).
// f = FREQ * fs / 65536. La muestra es +VOL si el bit 15 de la fase es 1, -VOL si es 0,
// y 0 cuando enable = 0.
module audio_nco (
    input  wire        clk,
    input  wire        rst,
    input  wire        carga,
    input  wire        enable,
    input  wire [15:0] freq,
    input  wire [6:0]  vol,
    output wire [7:0]  muestra
);
    reg  [15:0] fase;
    wire [15:0] fase_sig = fase + freq;

    always @(posedge clk) begin
        if (rst)
            fase <= 16'd0;
        else if (carga)
            fase <= fase_sig;
    end

    // La muestra usa la fase que se guarda en esta misma carga
    assign muestra = !enable     ? 8'd0 :
                     fase_sig[15] ? {1'b0, vol} :
                                    8'd0 - {1'b0, vol};
endmodule
