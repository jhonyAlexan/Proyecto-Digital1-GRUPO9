// peripheral_audio: módulo superior del periférico de audio (figura 6).
// Une audio_regs, audio_tiempos, audio_nco e i2s_tx con los nombres de los diagramas.
module peripheral_audio #(
    parameter CICLOS_BCLK = 16   // 16 con clk = 25 MHz, 18 con clk = 27 MHz
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        cs,
    input  wire        rd,
    input  wire        wr,
    input  wire [3:0]  addr,
    input  wire [31:0] d_in,
    output wire [31:0] d_out,
    output wire        ack,
    output wire        audio_bclk,
    output wire        audio_lrclk,
    output wire        audio_din
);
    wire [15:0] freq;
    wire [6:0]  vol;
    wire        enable;
    wire        tick_bajada;
    wire        carga;
    wire [4:0]  cnt_bit;
    wire [7:0]  muestra;

    audio_regs u_regs (
        .clk(clk), .rst(rst), .cs(cs), .rd(rd), .wr(wr), .addr(addr), .d_in(d_in),
        .d_out(d_out), .ack(ack), .freq(freq), .vol(vol), .enable(enable)
    );

    audio_tiempos #(.CICLOS_BCLK(CICLOS_BCLK)) u_tiempos (
        .clk(clk), .rst(rst), .audio_bclk(audio_bclk),
        .tick_bajada(tick_bajada), .cnt_bit(cnt_bit), .carga(carga)
    );

    audio_nco u_nco (
        .clk(clk), .rst(rst), .carga(carga), .enable(enable),
        .freq(freq), .vol(vol), .muestra(muestra)
    );

    i2s_tx u_i2s (
        .clk(clk), .rst(rst), .tick_bajada(tick_bajada), .carga(carga),
        .cnt_bit(cnt_bit), .muestra(muestra),
        .audio_lrclk(audio_lrclk), .audio_din(audio_din)
    );
endmodule
