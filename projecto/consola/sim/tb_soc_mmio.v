`timescale 1ns / 1ps

module tb_soc_mmio;
    reg  [31:0] mem_addr;
    wire [7:0]  cs;
    wire [31:0] mem_rdata;

    // Valores simulados de cada periférico
    wire [31:0] dout_uart  = 32'h0000_0040;
    wire [31:0] dout_gpio  = 32'h0000_0041;
    wire [31:0] dout_mult  = 32'h0000_002A; // Resultado multiplicador (6 * 7 = 42)
    wire [31:0] dout_audio = 32'h0000_0043;
    wire [31:0] dout_hub75 = 32'h0000_0044;
    wire [31:0] dout_flash = 32'h0000_0200; // done=1 en SPI_CTRL_STAT
    wire [31:0] dout_ram   = 32'hDEAD_BEEF;

    // Modelo de registros de mandos G5 (0x0047_0000 = P1, 0x0047_0004 = P2)
    wire [31:0] dout_joy   = (mem_addr[3:0] == 4'h0) ? 32'h0002_807F : // J1
                             (mem_addr[3:0] == 4'h4) ? 32'h0001_40FF : // J2
                                                       32'h0000_0000;

    chip_select dut (
        .mem_addr   (mem_addr),
        .chip0_dout (dout_uart),
        .chip1_dout (dout_gpio),
        .chip2_dout (dout_mult),
        .chip3_dout (dout_audio),
        .chip4_dout (dout_hub75),
        .chip5_dout (dout_flash),
        .chip6_dout (dout_ram),
        .chip7_dout (dout_joy),
        .cs         (cs),
        .mem_rdata  (mem_rdata)
    );

    initial begin
        // 1. Lectura Jugador 1 en 0x0047_0000
        mem_addr = 32'h0047_0000; #10;
        if (cs === 8'b1000_0000 && mem_rdata === 32'h0002_807F)
            $display("[PASA] 0x0047_0000 -> cs[7]=1, J1 = 0x%08h", mem_rdata);
        else
            $display("[FALLA] 0x0047_0000 -> cs=%b, rdata=0x%08h", cs, mem_rdata);

        // 2. Lectura Jugador 2 en 0x0047_0004
        mem_addr = 32'h0047_0004; #10;
        if (cs === 8'b1000_0000 && mem_rdata === 32'h0001_40FF)
            $display("[PASA] 0x0047_0004 -> cs[7]=1, J2 = 0x%08h", mem_rdata);
        else
            $display("[FALLA] 0x0047_0004 -> cs=%b, rdata=0x%08h", cs, mem_rdata);

        // 3. Verificación Multiplicador en 0x0042_0008
        mem_addr = 32'h0042_0008; #10;
        if (cs === 8'b0000_0100 && mem_rdata === 32'h0000_002A)
            $display("[PASA] 0x0042_0008 -> cs[2]=1, Mult = 0x%08h", mem_rdata);
        else
            $display("[FALLA] 0x0042_0008 -> cs=%b, rdata=0x%08h", cs, mem_rdata);

        // 4. Verificación Flash SPI en 0x0045_0000 y RAM en 0x0000_0100
        mem_addr = 32'h0045_0000; #10;
        if (cs === 8'b0010_0000 && mem_rdata === 32'h0000_0200)
            $display("[PASA] 0x0045_0000 -> cs[5]=1, Flash = 0x%08h", mem_rdata);
        else
            $display("[FALLA] 0x0045_0000 -> cs=%b, rdata=0x%08h", cs, mem_rdata);

        mem_addr = 32'h0000_0100; #10;
        if (cs === 8'b0100_0000 && mem_rdata === 32'hDEAD_BEEF)
            $display("[PASA] 0x0000_0100 -> cs[6]=1, RAM = 0x%08h", mem_rdata);
        else
            $display("[FALLA] 0x0000_0100 -> cs=%b, rdata=0x%08h", cs, mem_rdata);

        $finish;
    end
endmodule
