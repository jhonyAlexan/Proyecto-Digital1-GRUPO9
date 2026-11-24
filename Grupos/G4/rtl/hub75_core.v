// =============================================================================
// hub75_core.v — Núcleo del controlador HUB75 64x64 (barrido 1/32, RGB111)
//
// Sigue la división de las secciones 7 a 9 del README de G4:
//
//   hub75_core
//   ├── hub75_tick         generador de ticks (habilitación cada CLK_DIV ciclos)
//   ├── hub75_framebuffer  2 x (2048 x 3 bits), lectura síncrona
//   ├── hub75_ctrl         FSM de 6 estados + registros CLK, LAT, OE (sección 9)
//   └── hub75_datapath     contadores, comparadores, mux, RGB, ROW, frame (sección 8)
//
// El controlador manda al datapath las órdenes de la tabla de la sección 8
// (clear_col, inc_col, load_rgb, rgb_sel, load_row, clear_cnt, inc_cnt, inc_row)
// y recibe las condiciones de un bit (last_col, lat_zone1, lat_zone2, last_cnt,
// oe_on). Los nombres T1..T8 son las filas de la tabla de transferencias.
//
// Reloj: el de la consola (50 MHz en la Tang Primer 25K). rst: síncrono, activo
// en alto; no borra el framebuffer.
// =============================================================================
module hub75_core #(
    parameter CLK_DIV       = 2,       // ciclos de clk por tick (>= 2)
    parameter DISPLAY_TICKS = 1024     // DT: ticks de DISPLAY por fila
) (
    input  wire        clk,
    input  wire        rst,

    // Desde los registros del bus
    input  wire        enable,         // CONTROL.EN
    input  wire [ 9:0] brightness,     // BRIGHT
    input  wire        fb_we,          // escritura de un píxel
    input  wire [11:0] fb_waddr,       // {y[5:0], x[5:0]}
    input  wire [ 2:0] fb_wdata,       // {R, G, B}

    // Hacia los registros del bus
    output wire        busy,           // STATUS.BUSY = estado != IDLE
    output wire [31:0] frame_count,    // FRAME

    // Panel
    output wire [ 2:0] hub75_rgb0,     // R1 G1 B1
    output wire [ 2:0] hub75_rgb1,     // R2 G2 B2
    output wire [ 4:0] hub75_row,      // E D C B A (bit 0 = A)
    output wire        hub75_clk,
    output wire        hub75_lat,
    output wire        hub75_oe        // activo en bajo
);

    wire        tick;
    wire [10:0] fb_raddr;
    wire [ 2:0] top_q, bot_q;

    // Órdenes (control -> datapath)
    wire       clear_col, inc_col, load_rgb, load_row, clear_cnt, inc_cnt, inc_row;
    wire [1:0] rgb_sel;
    // Condiciones (datapath -> control)
    wire       last_col, lat_zone1, lat_zone2, last_cnt, oe_on;

    hub75_tick #(.CLK_DIV(CLK_DIV)) u_tick (
        .clk(clk), .rst(rst), .tick(tick)
    );

    hub75_framebuffer u_fb (
        .clk(clk),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .fb_raddr(fb_raddr), .top_q(top_q), .bot_q(bot_q)
    );

    hub75_ctrl u_ctrl (
        .clk(clk), .rst(rst), .tick(tick), .enable(enable),
        .last_col(last_col), .lat_zone1(lat_zone1), .lat_zone2(lat_zone2),
        .last_cnt(last_cnt), .oe_on(oe_on),
        .clear_col(clear_col), .inc_col(inc_col), .load_rgb(load_rgb), .rgb_sel(rgb_sel),
        .load_row(load_row), .clear_cnt(clear_cnt), .inc_cnt(inc_cnt), .inc_row(inc_row),
        .busy(busy),
        .hub75_clk(hub75_clk), .hub75_lat(hub75_lat), .hub75_oe(hub75_oe)
    );

    hub75_datapath #(.DISPLAY_TICKS(DISPLAY_TICKS)) u_dp (
        .clk(clk), .rst(rst),
        .clear_col(clear_col), .inc_col(inc_col), .load_rgb(load_rgb), .rgb_sel(rgb_sel),
        .load_row(load_row), .clear_cnt(clear_cnt), .inc_cnt(inc_cnt), .inc_row(inc_row),
        .brightness(brightness), .fb_top_q(top_q), .fb_bot_q(bot_q),
        .last_col(last_col), .lat_zone1(lat_zone1), .lat_zone2(lat_zone2),
        .last_cnt(last_cnt), .oe_on(oe_on),
        .fb_raddr(fb_raddr), .frame_count(frame_count),
        .hub75_rgb0(hub75_rgb0), .hub75_rgb1(hub75_rgb1), .hub75_row(hub75_row)
    );

endmodule


// =============================================================================
// Generador de ticks: un pulso de UN ciclo de clk cada CLK_DIV ciclos.
// No es un reloj: los demás bloques lo usan como habilitación.
// =============================================================================
module hub75_tick #(
    parameter CLK_DIV = 2
) (
    input  wire clk,
    input  wire rst,
    output reg  tick
);
    reg [7:0] cuenta;

    always @(posedge clk) begin
        if (rst) begin
            cuenta <= 0;
            tick   <= 1'b0;
        end else if (cuenta == CLK_DIV - 1) begin
            cuenta <= 0;
            tick   <= 1'b1;
        end else begin
            cuenta <= cuenta + 1'b1;
            tick   <= 1'b0;
        end
    end
endmodule


// =============================================================================
// Framebuffer: dos memorias de 2048 x 3 bits, una por mitad del panel.
//   Escritura: fb_waddr = {y, x}; y[5] (bit 11) elige la mitad.
//   Lectura:   fb_raddr = {r, col}; top_q y bot_q llegan un ciclo después.
// =============================================================================
module hub75_framebuffer (
    input  wire        clk,
    input  wire        fb_we,
    input  wire [11:0] fb_waddr,
    input  wire [ 2:0] fb_wdata,
    input  wire [10:0] fb_raddr,
    output reg  [ 2:0] top_q,
    output reg  [ 2:0] bot_q
);
    reg [2:0] mem_top [0:2047];
    reg [2:0] mem_bot [0:2047];

    // Imagen inicial en negro. Gowin no acepta bucles de más de 2000 vueltas,
    // por eso se llenan dos posiciones por vuelta.
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem_top[2*i] = 3'b000;  mem_top[2*i + 1] = 3'b000;
            mem_bot[2*i] = 3'b000;  mem_bot[2*i + 1] = 3'b000;
        end
    end

    always @(posedge clk) begin
        if (fb_we) begin
            if (fb_waddr[11]) mem_bot[fb_waddr[10:0]] <= fb_wdata;
            else              mem_top[fb_waddr[10:0]] <= fb_wdata;
        end
    end

    always @(posedge clk) begin
        top_q <= mem_top[fb_raddr];
        bot_q <= mem_bot[fb_raddr];
    end
endmodule


// =============================================================================
// Controlador (sección 9): FSM de 6 estados y registros de salida CLK, LAT, OE.
// Las órdenes al datapath son combinacionales (estado, tick, enable, CLK y
// condiciones) y se ejecutan en el próximo flanco de clk.
// =============================================================================
module hub75_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick,
    input  wire       enable,

    // Condiciones del datapath
    input  wire       last_col,      // col = 63
    input  wire       lat_zone1,     // col >= 53
    input  wire       lat_zone2,     // col >= 52
    input  wire       last_cnt,      // cnt = DT - 1
    input  wire       oe_on,         // cnt < BRIGHT

    // Órdenes al datapath
    output reg        clear_col,
    output reg        inc_col,
    output reg        load_rgb,
    output reg  [1:0] rgb_sel,       // 00 framebuffer, 01 patrón 1, 10 patrón 2
    output reg        load_row,
    output reg        clear_cnt,
    output reg        inc_cnt,
    output reg        inc_row,

    output wire       busy,

    // Líneas de control del panel (salidas registradas)
    output reg        hub75_clk,
    output reg        hub75_lat,
    output reg        hub75_oe
);
    localparam [2:0] IDLE    = 3'd0,
                     INIT1   = 3'd1,
                     INIT2   = 3'd2,
                     SHIFT   = 3'd3,
                     LATCH   = 3'd4,
                     DISPLAY = 3'd5;

    reg [2:0] estado, estado_sig;
    reg       clk_sig, lat_sig, oe_sig;

    assign busy = (estado != IDLE);

    // Bloque S (INIT1, INIT2, SHIFT): estado que sigue y zona de LAT
    wire       en_s     = (estado == INIT1) || (estado == INIT2) || (estado == SHIFT);
    wire [2:0] s_sig    = (estado == INIT1) ? INIT2 : (estado == INIT2) ? SHIFT : LATCH;
    wire       zona     = (estado == INIT1) ? lat_zone1 : (estado == INIT2) ? lat_zone2 : 1'b0;

    // ------------------------------------------------- Lógica de órdenes
    always @(*) begin
        // Valores por defecto: todo se mantiene (H1, H2)
        estado_sig = estado;
        clear_col  = 1'b0;
        inc_col    = 1'b0;
        load_rgb   = 1'b0;
        rgb_sel    = 2'b00;
        load_row   = 1'b0;
        clear_cnt  = 1'b0;
        inc_cnt    = 1'b0;
        inc_row    = 1'b0;
        clk_sig    = hub75_clk;
        lat_sig    = hub75_lat;
        oe_sig     = hub75_oe;

        // Fuente del dato según el estado del bloque S
        case (estado)
            INIT1:   rgb_sel = 2'b01;
            INIT2:   rgb_sel = 2'b10;
            default: rgb_sel = 2'b00;
        endcase

        if (tick) begin
            case (estado)
                IDLE: if (enable) begin                   // T1
                    clear_col  = 1'b1;
                    estado_sig = INIT1;
                end

                INIT1, INIT2, SHIFT: begin
                    if (hub75_clk) begin                  // T2: presentar el dato
                        load_rgb = 1'b1;
                        lat_sig  = zona;
                        clk_sig  = 1'b0;
                    end else if (!last_col) begin         // T3: capturar y avanzar
                        inc_col  = 1'b1;
                        clk_sig  = 1'b1;
                    end else begin                        // T4: última columna
                        clear_col  = 1'b1;
                        clk_sig    = 1'b1;
                        estado_sig = s_sig;
                    end
                end

                LATCH: begin                              // T5
                    load_row   = 1'b1;
                    clear_cnt  = 1'b1;
                    lat_sig    = 1'b1;
                    estado_sig = DISPLAY;
                end

                DISPLAY: begin
                    lat_sig = 1'b0;
                    if (!last_cnt) begin                  // T6
                        inc_cnt = 1'b1;
                        oe_sig  = ~oe_on;
                    end else begin                        // T7 / T8
                        clear_cnt  = 1'b1;
                        inc_row    = 1'b1;
                        oe_sig     = 1'b1;
                        estado_sig = enable ? SHIFT : IDLE;
                    end
                end

                default: estado_sig = IDLE;
            endcase
        end
    end

    // ------------------------------------------- Registro de estado y salidas
    always @(posedge clk) begin
        if (rst) begin                                    // R
            estado    <= IDLE;
            hub75_clk <= 1'b1;
            hub75_lat <= 1'b0;
            hub75_oe  <= 1'b1;
        end else begin
            estado    <= estado_sig;
            hub75_clk <= clk_sig;
            hub75_lat <= lat_sig;
            hub75_oe  <= oe_sig;
        end
    end
endmodule


// =============================================================================
// Datapath (sección 8): ejecuta las órdenes del controlador y le devuelve
// condiciones de un bit. No recibe tick ni enable.
// =============================================================================
module hub75_datapath #(
    parameter DISPLAY_TICKS = 1024
) (
    input  wire        clk,
    input  wire        rst,

    // Órdenes
    input  wire        clear_col,
    input  wire        inc_col,
    input  wire        load_rgb,
    input  wire [ 1:0] rgb_sel,
    input  wire        load_row,
    input  wire        clear_cnt,
    input  wire        inc_cnt,
    input  wire        inc_row,

    // Datos
    input  wire [ 9:0] brightness,
    input  wire [ 2:0] fb_top_q,
    input  wire [ 2:0] fb_bot_q,

    // Condiciones
    output wire        last_col,
    output wire        lat_zone1,
    output wire        lat_zone2,
    output wire        last_cnt,
    output wire        oe_on,

    // Salidas
    output wire [10:0] fb_raddr,
    output reg  [31:0] frame_count,
    output wire [ 2:0] hub75_rgb0,
    output wire [ 2:0] hub75_rgb1,
    output reg  [ 4:0] hub75_row
);
    localparam integer CW = (DISPLAY_TICKS > 1) ? $clog2(DISPLAY_TICKS) : 1;

    // Palabras de configuración del driver (bit col mod 16)
    localparam [15:0] PATRON1 = 16'hFFFE;   // 0,1,1,...,1
    localparam [15:0] PATRON2 = 16'h0200;   // solo el bit 9

    reg [5:0]    col;
    reg [4:0]    r;
    reg [CW-1:0] cnt;
    reg [5:0]    rgb;                       // {R1 G1 B1, R2 G2 B2}

    // ---------------------------------------------------------- Comparadores
    assign last_col  = (col == 6'd63);
    assign lat_zone1 = (col >= 6'd53);
    assign lat_zone2 = (col >= 6'd52);
    assign last_cnt  = (cnt == DISPLAY_TICKS - 1);
    assign oe_on     = ({{(32-CW){1'b0}}, cnt} < {22'd0, brightness});

    // ------------------------------------------------------- Mux 3:1 de datos
    reg [5:0] dato;
    always @(*) begin
        case (rgb_sel)
            2'b01:   dato = {6{PATRON1[col[3:0]]}};
            2'b10:   dato = {6{PATRON2[col[3:0]]}};
            default: dato = {fb_top_q, fb_bot_q};
        endcase
    end

    assign fb_raddr   = {r, col};
    assign hub75_rgb0 = rgb[5:3];
    assign hub75_rgb1 = rgb[2:0];

    // ------------------------------------------------------------ Registros
    always @(posedge clk) begin
        if (rst) begin
            col         <= 0;
            r           <= 0;
            cnt         <= 0;
            rgb         <= 0;
            hub75_row   <= 0;
            frame_count <= 0;
        end else begin
            if (clear_col)    col <= 0;
            else if (inc_col) col <= col + 1'b1;

            if (clear_cnt)    cnt <= 0;
            else if (inc_cnt) cnt <= cnt + 1'b1;

            if (inc_row) begin
                r <= r + 1'b1;                       // 31 -> 0 por desborde
                if (r == 5'd31) frame_count <= frame_count + 1'b1;
            end

            if (load_rgb) rgb       <= dato;
            if (load_row) hub75_row <= r;
        end
    end
endmodule
