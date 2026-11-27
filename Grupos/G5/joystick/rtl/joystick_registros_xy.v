// joystick_registros_xy: guarda el último X y el último Y válidos y los entrega por dirección.
// X en DIR_X (0x0042) e Y en DIR_Y (0x0043), cada uno de 8 bits con signo (-127 a 127).
// Lectura: se pone dir y leer = 1 durante un ciclo; en el ciclo siguiente dato trae el valor
// y listo vale 1. Una dirección que no es ninguna de las dos se lee como 0.
module joystick_registros_xy #(
    parameter [15:0] DIR_X = 16'h0042,
    parameter [15:0] DIR_Y = 16'h0043
) (
    input  wire        clk,
    input  wire        rst,
    // Desde el ensamblador
    input  wire        cargar,          // paquete válido: guardar la muestra
    input  wire [31:0] datos_muestra,   // {secuencia, 6'b0, ataque, boton, eje_y, eje_x}
    // Puerto de lectura por dirección
    input  wire [15:0] dir,
    input  wire        leer,
    output reg  [7:0]  dato,
    output reg         listo,
    // Valores guardados, para quien prefiera conectarlos directo
    output reg  [7:0]  eje_x,
    output reg  [7:0]  eje_y,
    output reg         boton
);
    always @(posedge clk) begin
        if (rst) begin
            eje_x <= 8'd0;
            eje_y <= 8'd0;
            boton <= 1'b0;
        end else if (cargar) begin
            eje_x <= datos_muestra[7:0];
            eje_y <= datos_muestra[15:8];
            boton <= datos_muestra[16];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            dato  <= 8'd0;
            listo <= 1'b0;
        end else begin
            listo <= leer;
            if (leer) begin
                case (dir)
                    DIR_X:   dato <= eje_x;
                    DIR_Y:   dato <= eje_y;
                    default: dato <= 8'd0;
                endcase
            end
        end
    end
endmodule
