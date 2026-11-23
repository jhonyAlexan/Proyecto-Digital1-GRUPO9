// Ensambla los campos. El banco captura la muestra en el flanco que acepta el byte 7.
module joystick_ensamblador #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer T_MAX_CICLOS = CLK_HZ / 1000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_frame_err,
    output wire [31:0] datos_muestra,
    output wire        cargar_p1,
    output wire        cargar_p2,
    output wire        checksum_error
);
    localparam [1:0] BUSCAR = 0, CAMPOS = 1, CHECKSUM = 2;
    localparam integer ANCHO = (T_MAX_CICLOS > 1) ? $clog2(T_MAX_CICLOS) : 1;

    reg [1:0] estado;
    reg [2:0] indice;
    reg [ANCHO-1:0] espera;
    reg [7:0] jugador, secuencia, eje_x, eje_y, xor_campos;
    reg boton, ataque;
    wire es_cabecera;
    wire evaluar = !rst && !rx_frame_err && rx_valid && (estado == CHECKSUM);

    assign datos_muestra = {secuencia, 6'b0, ataque, boton, eje_y, eje_x};

    joystick_validador u_validador (
        .rx_data(rx_data), .jugador(jugador), .xor_campos(xor_campos),
        .evaluar(evaluar), .es_cabecera(es_cabecera),
        .cargar_p1(cargar_p1), .cargar_p2(cargar_p2),
        .checksum_error(checksum_error)
    );

    always @(posedge clk) begin
        if (rst) begin
            estado <= BUSCAR;
            espera <= 0;
            indice <= 0;
            xor_campos <= 0;
            jugador <= 0;
            secuencia <= 0;
            eje_x <= 0;
            eje_y <= 0;
            boton <= 0;
            ataque <= 0;
        end else if (rx_frame_err) begin
            estado <= BUSCAR;
            espera <= 0;
        end else if (rx_valid) begin
            espera <= 0;
            case (estado)
                BUSCAR: if (es_cabecera) begin
                    indice <= 1;
                    xor_campos <= 0;
                    estado <= CAMPOS;
                end

                CAMPOS: begin
                    xor_campos <= xor_campos ^ rx_data;
                    case (indice)
                        1: jugador   <= rx_data;
                        2: secuencia <= rx_data;
                        3: eje_x     <= rx_data;
                        4: eje_y     <= rx_data;
                        5: boton     <= rx_data[0];
                        6: ataque    <= rx_data[0];
                    endcase
                    if (indice == 6)
                        estado <= CHECKSUM;
                    else
                        indice <= indice + 1'b1;
                end

                CHECKSUM: estado <= BUSCAR;
                default:  estado <= BUSCAR;
            endcase
        end else if (estado != BUSCAR) begin
            if (espera == T_MAX_CICLOS - 1) begin
                estado <= BUSCAR;
                espera <= 0;
            end else begin
                espera <= espera + 1'b1;
            end
        end
    end
endmodule
