python3 -c '
tb = """`timescale 1ns / 1ps
module tb_imu;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [15:0] tx_data = 16'\''h8000;
    wire [7:0] rx_data;
    wire done;
    wire sclk, mosi, cs_n;
    reg miso = 0;

    spi_master dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .tx_data(tx_data),
        .rx_data(rx_data), .done(done),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    always #18.5 clk = ~clk;

    reg [7:0] resp_sensor = 8'\''hD1;
    integer i;

    initial begin
        $dumpfile("ondas_spi.vcd");
        $dumpvars(0, tb_imu);

        #100 rst_n = 1;
        #100;

        start = 1;
        #37 start = 0;

        repeat(8) @(negedge sclk);
        for (i = 7; i >= 0; i = i - 1) begin
            miso = resp_sensor[i];
            @(negedge sclk);
        end

        #1000;
        $finish;
    end
endmodule
"""
open("tb_imu.v", "w").write(tb)
'
