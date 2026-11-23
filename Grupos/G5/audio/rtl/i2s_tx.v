// i2s_tx: máquina de estados IZQ/DER y registro de desplazamiento de 32 bits (3.6).
// Trama: {muestra, 8'h00} en el slot izquierdo y lo mismo en el derecho, MSB primero.
// LRCLK es la salida de la máquina (Moore) y cambia un BCLK antes del MSB de cada palabra.
module i2s_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_bajada,
    input  wire       carga,
    input  wire [4:0] cnt_bit,
    input  wire [7:0] muestra,
    output wire       audio_lrclk,
    output wire       audio_din
);
    localparam IZQ = 1'b0, DER = 1'b1;

    reg        estado;
    reg [31:0] desplaza;

    assign audio_lrclk = estado;
    assign audio_din   = desplaza[31];

    always @(posedge clk) begin
        if (rst) begin
            estado   <= IZQ;
            desplaza <= 32'd0;
        end else if (tick_bajada) begin
            // Ruta de datos: cargar la trama nueva o desplazar un bit
            if (carga)
                desplaza <= {muestra, 8'h00, muestra, 8'h00};
            else
                desplaza <= {desplaza[30:0], 1'b0};
            // Control: cambio de canal en los bits 14 y 30
            case (estado)
                IZQ: if (cnt_bit == 5'd14) estado <= DER;
                DER: if (cnt_bit == 5'd30) estado <= IZQ;
            endcase
        end
    end
endmodule
