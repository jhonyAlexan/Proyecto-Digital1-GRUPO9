module detector_golpe #(
    parameter [18:0] UMBRAL_GOLPE    = 19'd65000,
    parameter [23:0] PULSO_ALTO_CLK  = 24'd4_050_000,
    parameter [23:0] COOLDOWN_CLK    = 24'd2_700_000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed [15:0] gx, gy, gz,
    input  wire signed [15:0] ax, ay, az,
    output reg                golpe_out,
    output wire [18:0]        energia_out
);

    wire [15:0] abs_gx = gx[15] ? (~gx + 16'd1) : gx;
    wire [15:0] abs_gy = gy[15] ? (~gy + 16'd1) : gy;
    wire [15:0] abs_gz = gz[15] ? (~gz + 16'd1) : gz;

    reg signed [15:0] prev_ax, prev_ay, prev_az;
    wire signed [16:0] diff_ax = ax - prev_ax;
    wire signed [16:0] diff_ay = ay - prev_ay;
    wire signed [16:0] diff_az = az - prev_az;

    wire [16:0] abs_dax = diff_ax[16] ? (~diff_ax + 17'd1) : diff_ax;
    wire [16:0] abs_day = diff_ay[16] ? (~diff_ay + 17'd1) : diff_ay;
    wire [16:0] abs_daz = diff_az[16] ? (~diff_az + 17'd1) : diff_az;

    wire [18:0] energia_mov = (abs_gx + abs_gy + abs_gz) + (abs_dax + abs_day + abs_daz);
    assign energia_out = energia_mov;

    reg [1:0]  st;
    reg [23:0] timer;

    localparam ST_LISTO    = 2'd0,
               ST_PULSO    = 2'd1,
               ST_COOLDOWN = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_ax   <= 16'd0;
            prev_ay   <= 16'd0;
            prev_az   <= 16'd0;
            golpe_out <= 1'b0;
            st        <= ST_LISTO;
            timer     <= 24'd0;
        end else begin
            if (sample_valid) begin
                prev_ax <= ax;
                prev_ay <= ay;
                prev_az <= az;
            end

            case (st)
                ST_LISTO: begin
                    golpe_out <= 1'b0;
                    if (sample_valid && (energia_mov > UMBRAL_GOLPE)) begin
                        golpe_out <= 1'b1;
                        timer     <= 24'd0;
                        st        <= ST_PULSO;
                    end
                end

                ST_PULSO: begin
                    golpe_out <= 1'b1;
                    if (timer == PULSO_ALTO_CLK) begin
                        golpe_out <= 1'b0;
                        timer     <= 24'd0;
                        st        <= ST_COOLDOWN;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                ST_COOLDOWN: begin
                    golpe_out <= 1'b0;
                    if (timer == COOLDOWN_CLK) begin
                        st <= ST_LISTO;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                default: st <= ST_LISTO;
            endcase
        end
    end

endmodule
