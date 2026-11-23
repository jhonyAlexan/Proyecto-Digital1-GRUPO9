// Validador combinacional del paquete definido en la sección 3.2.3.
module joystick_validador (
    input  wire [7:0] rx_data,
    input  wire [7:0] jugador,
    input  wire [7:0] xor_campos,
    input  wire       evaluar,
    output wire       es_cabecera,
    output wire       cargar_p1,
    output wire       cargar_p2,
    output wire       checksum_error
);
    wire xor_correcto = (rx_data == xor_campos);

    assign es_cabecera    = (rx_data == 8'hAA);
    assign cargar_p1      = evaluar && xor_correcto && (jugador == 8'd1);
    assign cargar_p2      = evaluar && xor_correcto && (jugador == 8'd2);
    assign checksum_error = evaluar && !xor_correcto;
endmodule
