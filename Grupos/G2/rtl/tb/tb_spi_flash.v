// ============================================================================
// Archivo: Grupos/G2/rtl/tb/tb_spi_flash.v
// Descripción: Banco de pruebas autoverificado para peripheral_spi_flash y
//              spi_flash_controller. Cada caso valida filas específicas de la
//              tabla de transferencias RT (T0-T12) del ASMD de G2.
// ============================================================================

`timescale 1ns / 1ps

module tb_spi_flash;

    localparam real    CLK_HALF_PERIOD = 18.5185; // 27 MHz
    localparam integer TICK_DIV        = 4;       // f_SCLK = 3.375 MHz

    // Direcciones MMIO del periférico Flash SPI (Base 0x0045_0000)
    localparam [31:0] REG_CTRL_STAT = 32'h0045_0000;
    localparam [31:0] REG_CMD_ADDR  = 32'h0045_0004;
    localparam [31:0] REG_TX_DATA   = 32'h0045_0008;
    localparam [31:0] REG_RX_DATA   = 32'h0045_000C;

    reg         clk;
    reg         rst;
    reg         cs;
    reg         rd;
    reg  [31:0] addr;
    reg  [31:0] d_in;
    reg  [3:0]  wmask;
    wire [31:0] d_out;

    wire        spi_cs_n;
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;

    integer     tests_passed;
    integer     tests_failed;
    reg  [31:0] rdata;

    peripheral_spi_flash #(
        .TICK_DIV(TICK_DIV)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .cs       (cs),
        .rd       (rd),
        .addr     (addr),
        .d_in     (d_in),
        .wmask    (wmask),
        .d_out    (d_out),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

    initial clk = 1'b0;
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ========================================================================
    // Modelo comportamental corregido de Flash SPI W25Q64JV (Modo 0)
    // ========================================================================
    reg [7:0]  flash_mem [0:255];
    reg [7:0]  mosi_log  [0:31];
    integer    total_mosi_bytes;

    reg [2:0]  slave_bit_cnt;
    integer    slave_byte_cnt;
    reg [7:0]  slave_shift_in;
    reg [7:0]  next_shift_in;
    reg [7:0]  slave_cmd;
    reg [23:0] slave_addr;
    reg [7:0]  slave_tx_shift;

    always @(negedge spi_cs_n) begin
        slave_bit_cnt  <= 3'd0;
        slave_byte_cnt <= 0;
        slave_shift_in <= 8'h00;
        slave_cmd      <= 8'h00;
        slave_addr     <= 24'h000000;
        slave_tx_shift <= 8'h00;
        spi_miso       <= 1'b0;
    end

    always @(posedge spi_cs_n) begin
        spi_miso <= 1'b0;
    end

    // Muestreo de MOSI en flanco de subida de SCLK (un único desplazamiento por bit)
    always @(posedge spi_sclk) begin
        if (!spi_cs_n) begin
            next_shift_in  = {slave_shift_in[6:0], spi_mosi};
            slave_shift_in <= next_shift_in;

            if (slave_bit_cnt == 3'd7) begin
                mosi_log[total_mosi_bytes] <= next_shift_in;
                total_mosi_bytes           <= total_mosi_bytes + 1;

                if (slave_byte_cnt == 0)
                    slave_cmd <= next_shift_in;
                else if (slave_byte_cnt == 1)
                    slave_addr[23:16] <= next_shift_in;
                else if (slave_byte_cnt == 2)
                    slave_addr[15:8] <= next_shift_in;
                else if (slave_byte_cnt == 3)
                    slave_addr[7:0] <= next_shift_in;

                slave_byte_cnt <= slave_byte_cnt + 1;
                slave_bit_cnt  <= 3'd0;
            end else begin
                slave_bit_cnt <= slave_bit_cnt + 3'd1;
            end
        end
    end

    // Actualización de MISO en flanco de bajada de SCLK (CPHA = 0)
    always @(negedge spi_sclk) begin
        if (!spi_cs_n) begin
            if (slave_bit_cnt == 3'd0) begin
                if (slave_cmd == 8'h03 && slave_byte_cnt == 4) begin
                    slave_tx_shift <= flash_mem[slave_addr[7:0]];
                    spi_miso       <= flash_mem[slave_addr[7:0]][7];
                end else if (slave_cmd == 8'h03 && slave_byte_cnt > 4) begin
                    slave_addr     <= slave_addr + 24'd1;
                    slave_tx_shift <= flash_mem[slave_addr[7:0] + 8'd1];
                    spi_miso       <= flash_mem[slave_addr[7:0] + 8'd1][7];
                end else begin
                    spi_miso <= 1'b0;
                end
            end else begin
                slave_tx_shift <= {slave_tx_shift[6:0], 1'b0};
                spi_miso       <= slave_tx_shift[6];
            end
        end
    end

    // ========================================================================
    // Tareas de acceso MMIO y verificación
    // ========================================================================
    task mmio_write;
        input [31:0] waddr;
        input [31:0] wdata;
        begin
            @(negedge clk);
            cs    = 1'b1;
            rd    = 1'b0;
            wmask = 4'b1111;
            addr  = waddr;
            d_in  = wdata;
            @(posedge clk);
            #1;
            cs    = 1'b0;
            wmask = 4'b0000;
            d_in  = 32'd0;
        end
    endtask

    task mmio_read;
        input  [31:0] raddr;
        output [31:0] rdata_out;
        begin
            @(negedge clk);
            cs    = 1'b1;
            rd    = 1'b1;
            wmask = 4'b0000;
            addr  = raddr;
            @(posedge clk);
            #1;
            rdata_out = d_out;
            cs        = 1'b0;
            rd        = 1'b0;
        end
    endtask

    task wait_spi_done;
        output [31:0] status_out;
        integer guard;
        begin
            guard = 0;
            status_out = 32'd0;
            while (status_out[9] == 1'b0 && guard < 2000) begin
                mmio_read(REG_CTRL_STAT, status_out);
                guard = guard + 1;
            end
            if (guard >= 2000) begin
                $display("[FALLA] Timeout esperando bandera done=1 (T12)");
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    task check_equal;
        input [31:0]     actual;
        input [31:0]     expected;
        input [8*72-1:0] msg;
        begin
            if (actual === expected) begin
                $display("[PASA]  %0s (valor = 0x%08h)", msg, actual);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FALLA] %0s -> esperado: 0x%08h, obtenido: 0x%08h",
                         msg, expected, actual);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // ========================================================================
    // Casos de prueba ligados a las transiciones T0-T12 del ASMD
    // ========================================================================
    integer i;
    initial begin
        $dumpfile("tb_spi_flash.vcd");
        $dumpvars(0, tb_spi_flash);

        tests_passed     = 0;
        tests_failed     = 0;
        total_mosi_bytes = 0;

        for (i = 0; i < 256; i = i + 1)
            flash_mem[i] = 8'hFF;
        flash_mem[8'h10] = 8'hA5;
        flash_mem[8'h11] = 8'h3C;
        flash_mem[8'h12] = 8'h7E;

        // CASO 1: T0 (Reset síncrono) y T1 (Reposo IDLE)
        $display("\n--- CASO 1: Reset sincrono (T0) y reposo IDLE (T1) ---");
        rst   = 1'b1;
        cs    = 1'b0;
        rd    = 1'b0;
        wmask = 4'b0000;
        addr  = 32'd0;
        d_in  = 32'd0;
        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        check_equal({31'd0, spi_cs_n}, 32'd1, "T0/T1: spi_cs_n=1 en IDLE");
        check_equal({29'd0, dut.u_spi_core.u_fsm_control.state}, 32'd0,
                    "T0/T1: FSM en estado IDLE (000)");
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal(rdata[9:8], 2'b00, "T0/T1: busy=0 y done=0 tras reset");

        // CASO 2: T2 -> T3 -> T4..T10 -> T11 -> T12 con WREN 0x06 (len = 1)
        $display("\n--- CASO 2: WREN 0x06 (len=1) y retencion de done (T2, T11, T12) ---");
        total_mosi_bytes = 0;
        mmio_write(REG_CMD_ADDR, {8'h06, 24'h000000});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001); // start=1, cs_hold=0

        @(posedge clk);
        #1;
        check_equal({29'd0, dut.u_spi_core.u_datapath.len}, 32'd1,
                    "T2: Decodificacion dinamica len=1 para opcode 0x06");

        wait_spi_done(rdata);
        check_equal(rdata[9:8], 2'b10, "T12: done=1 y busy=0 al terminar WREN");
        check_equal({31'd0, spi_cs_n}, 32'd1, "T12: spi_cs_n=1 al cerrar trama");
        check_equal({31'd0, total_mosi_bytes}, 32'd1, "T10: Exactamente 1 byte enviado");
        check_equal({24'd0, mosi_log[0]}, 32'h0000_0006, "T4-T8: MOSI = 0x06");

        repeat (10) @(posedge clk);
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal({31'd0, rdata[9]}, 32'd1, "T1: done retenido en registro");

        // CASO 3: T2 (limpieza de done) y T9 (avance multibyte) con Sector Erase 0x20 (len = 4)
        $display("\n--- CASO 3: Sector Erase 0x20 (len=4) y limpieza de done (T2, T9) ---");
        total_mosi_bytes = 0;
        mmio_write(REG_CMD_ADDR, {8'h20, 24'h7F0000});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001);

        @(posedge clk);
        #1;
        check_equal({29'd0, dut.u_spi_core.u_datapath.len}, 32'd4,
                    "T2: Decodificacion dinamica len=4 para opcode 0x20");
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal(rdata[9:8], 2'b01, "T2: Limpieza inmediata done=0 y busy=1");

        wait_spi_done(rdata);
        check_equal({31'd0, total_mosi_bytes}, 32'd4, "T9/T10: 4 bytes enviados");
        check_equal({24'd0, mosi_log[0]}, 32'h0000_0020, "T9: Byte 0 MOSI = 0x20");
        check_equal({24'd0, mosi_log[1]}, 32'h0000_007F, "T9: Byte 1 MOSI = 0x7F");
        check_equal({24'd0, mosi_log[2]}, 32'h0000_0000, "T9: Byte 2 MOSI = 0x00");
        check_equal({24'd0, mosi_log[3]}, 32'h0000_0000, "T9: Byte 3 MOSI = 0x00");

        // CASO 4: Read Data 0x03 (len = 5) y muestreo MISO en T6
        $display("\n--- CASO 4: Read Data 0x03 (len=5) desde 0x000010 (T2, T6, T12) ---");
        total_mosi_bytes = 0;
        mmio_write(REG_TX_DATA, 32'h0000_0000);
        mmio_write(REG_CMD_ADDR, {8'h03, 24'h000010});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001);

        wait_spi_done(rdata);
        check_equal({31'd0, total_mosi_bytes}, 32'd5, "T10: 5 bytes transferidos (40 bits)");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_00A5, "T6/T12: SPI_RX_DATA = 0xA5");

        // CASO 5: Lectura continua en ráfaga con cs_hold = 1 en T12
        $display("\n--- CASO 5: Lectura continua en rafaga con cs_hold = 1 (T12) ---");
        mmio_write(REG_CMD_ADDR, {8'h03, 24'h000010});
        mmio_write(REG_CTRL_STAT, 32'h0000_0003); // start=1, cs_hold=1
        wait_spi_done(rdata);

        check_equal({31'd0, spi_cs_n}, 32'd0,
                    "T12 (cs_hold=1): spi_cs_n retenido en bajo tras primer byte");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_00A5, "T12 (cs_hold=1): Primer byte = 0xA5");

        mmio_write(REG_CMD_ADDR, {8'h00, 24'h000000}); // len=1
        mmio_write(REG_CTRL_STAT, 32'h0000_0001);      // start=1, cs_hold=0
        wait_spi_done(rdata);

        check_equal({31'd0, spi_cs_n}, 32'd1,
                    "T12 (cs_hold=0): spi_cs_n liberado al cerrar rafaga");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_003C, "T12 (cs_hold=0): Segundo byte = 0x3C");

        $display("\n====================================================");
        $display(" RESUMEN SIMULACION G2 SPI FLASH: %0d PASA | %0d FALLA",
                 tests_passed, tests_failed);
        $display("====================================================\n");

        if (tests_failed == 0)
            $display("RESULTADO GLOBAL: PASA");
        else
            $display("RESULTADO GLOBAL: FALLA");

        $finish;
    end

    initial begin
        #5000000;
        $display("[FALLA] Watchdog timeout excedido");
        $finish;
    end

endmodule
