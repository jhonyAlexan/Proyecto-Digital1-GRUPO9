// audio_regs: registros FREQ, VOL y CONTROL del periférico de audio (sección 3.3).
// Escritura y lectura en un ciclo; ack y d_out quedan listos el ciclo siguiente a cs.
module audio_regs (
    input  wire        clk,
    input  wire        rst,
    input  wire        cs,
    input  wire        rd,
    input  wire        wr,
    input  wire [3:0]  addr,
    input  wire [31:0] d_in,
    output reg  [31:0] d_out,
    output reg         ack,
    output reg  [15:0] freq,
    output reg  [6:0]  vol,
    output reg         enable
);
    localparam R_FREQ = 2'd0, R_VOL = 2'd1, R_CONTROL = 2'd2;

    always @(posedge clk) begin
        if (rst) begin
            freq   <= 16'd0;
            vol    <= 7'd0;
            enable <= 1'b0;
            d_out  <= 32'd0;
            ack    <= 1'b0;
        end else begin
            ack <= cs;
            if (cs && wr) begin
                case (addr[3:2])
                    R_FREQ:    freq   <= d_in[15:0];
                    R_VOL:     vol    <= d_in[6:0];
                    R_CONTROL: enable <= d_in[0];
                    default:   ;
                endcase
            end
            if (cs && rd) begin
                case (addr[3:2])
                    R_FREQ:    d_out <= {16'd0, freq};
                    R_VOL:     d_out <= {25'd0, vol};
                    R_CONTROL: d_out <= {31'd0, enable};
                    default:   d_out <= 32'd0;
                endcase
            end
        end
    end
endmodule
