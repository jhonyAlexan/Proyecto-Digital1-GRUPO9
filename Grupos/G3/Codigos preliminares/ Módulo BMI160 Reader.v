///////////////////////////////////////////////////////////////////////////////
// Módulo:       BMI160_Reader
// Descripción:  FSM que lee acelerómetro y giroscopio del BMI160 por SPI,
//               y deja los datos crudos en registros MMIO para el FemtoRV.
Codigo Realizado, con IA, extraer diagrama de flujo y revisar con el profesor
///////////////////////////////////////////////////////////////////////////////

module BMI160_Reader
  #(
    parameter CLK_FREQ_HZ      = 27_000_000,
    parameter SPI_FREQ_HZ      = 3_375_000,
    parameter SAMPLE_RATE_HZ   = 200,
    parameter CLKS_PER_HALF_BIT = CLK_FREQ_HZ / (SPI_FREQ_HZ * 2),
    parameter SAMPLE_TICKS     = CLK_FREQ_HZ / SAMPLE_RATE_HZ,
    parameter INIT_ACCEL_TICKS = CLK_FREQ_HZ / 200,         // 5ms
    parameter INIT_GYRO_TICKS  = CLK_FREQ_HZ / 1000 * 80    // 80ms
  )
  (
    input        i_Clk,
    input        i_Rst_L,

    output       o_SPI_Clk,
    output       o_SPI_MOSI,
    input        i_SPI_MISO,
    output       o_SPI_CS_n,

    output reg [15:0] o_ACC_X,
    output reg [15:0] o_ACC_Y,
    output reg [15:0] o_ACC_Z,
    output reg [15:0] o_GYR_X,
    output reg [15:0] o_GYR_Y,
    output reg [15:0] o_GYR_Z,
    
    output reg        o_Data_Ready_Latch,
    input             i_Clear_Ready
  );

  localparam ST_INIT_ACCEL    = 4'd0;
  localparam ST_WAIT_ACCEL    = 4'd1;
  localparam ST_INIT_GYRO     = 4'd2;
  localparam ST_WAIT_GYRO     = 4'd3;
  localparam ST_WAIT_SAMPLE   = 4'd4;
  localparam ST_READ_GYRO     = 4'd5;
  localparam ST_WAIT_GYRO_RX  = 4'd6;
  localparam ST_READ_ACCEL    = 4'd7;
  localparam ST_WAIT_ACCEL_RX = 4'd8;
  localparam ST_STORE         = 4'd9;

  reg [3:0] r_State;
  reg [24:0] r_Wait_Count;

  reg        r_TX_DV;
  reg [7:0]  r_TX_Byte;
  reg [2:0]  r_TX_Count;
  wire       w_TX_Ready;
  wire       w_RX_DV;
  wire [7:0] w_RX_Byte;
  wire [2:0] w_RX_Count;

  // Instancia del SPI Master con CS (asume que el archivo del módulo está en tu proyecto)
  SPI_Master_With_Single_CS
    #(
      .SPI_MODE         (0),
      .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT),
      .MAX_BYTES_PER_CS (7),
      .CS_INACTIVE_CLKS (10)
    )
    SPI_Inst
    (
      .i_Rst_L    (i_Rst_L),
      .i_Clk      (i_Clk),
      .i_TX_Count (r_TX_Count),
      .i_TX_Byte  (r_TX_Byte),
      .i_TX_DV    (r_TX_DV),
      .o_TX_Ready (w_TX_Ready),
      .o_RX_Count (w_RX_Count),
      .o_RX_DV    (w_RX_DV),
      .o_RX_Byte  (w_RX_Byte),
      .o_SPI_Clk  (o_SPI_Clk),
      .i_SPI_MISO (i_SPI_MISO),
      .o_SPI_MOSI (o_SPI_MOSI),
      .o_SPI_CS_n (o_SPI_CS_n)
    );

  reg [7:0] r_GYR_X_L, r_GYR_X_H;
  reg [7:0] r_GYR_Y_L, r_GYR_Y_H;
  reg [7:0] r_GYR_Z_L, r_GYR_Z_H;
  reg [7:0] r_ACC_X_L, r_ACC_X_H;
  reg [7:0] r_ACC_Y_L, r_ACC_Y_H;
  reg [7:0] r_ACC_Z_L, r_ACC_Z_H;

  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_State              <= ST_INIT_ACCEL;
      r_Wait_Count         <= 0;
      r_TX_DV              <= 1'b0;
      r_TX_Byte            <= 8'h00;
      r_TX_Count           <= 3'd0;
      o_Data_Ready_Latch   <= 1'b0;
      o_ACC_X <= 16'h0; o_ACC_Y <= 16'h0; o_ACC_Z <= 16'h0;
      o_GYR_X <= 16'h0; o_GYR_Y <= 16'h0; o_GYR_Z <= 16'h0;
    end
    else
    begin
      r_TX_DV <= 1'b0;

      if (i_Clear_Ready)
        o_Data_Ready_Latch <= 1'b0;

      case (r_State)

        ST_INIT_ACCEL:
        begin
          if (w_TX_Ready)
          begin
            r_TX_Count <= 3'd2;
            r_TX_Byte  <= 8'h7E;
            r_TX_DV    <= 1'b1;
            r_State    <= ST_WAIT_ACCEL;
            r_Wait_Count <= 0;
          end
        end

        ST_WAIT_ACCEL:
        begin
          if (w_TX_Ready && r_Wait_Count == 0)
          begin
            r_TX_Byte <= 8'h11;
            r_TX_DV   <= 1'b1;
            r_Wait_Count <= 1;
          end
          else if (r_Wait_Count > 0)
          begin
            r_Wait_Count <= r_Wait_Count + 1;
            if (r_Wait_Count == INIT_ACCEL_TICKS)
            begin
              r_Wait_Count <= 0;
              r_State      <= ST_INIT_GYRO;
            end
          end
        end

        ST_INIT_GYRO:
        begin
          if (w_TX_Ready)
          begin
            r_TX_Count <= 3'd2;
            r_TX_Byte  <= 8'h7E;
            r_TX_DV    <= 1'b1;
            r_State    <= ST_WAIT_GYRO;
            r_Wait_Count <= 0;
          end
        end

        ST_WAIT_GYRO:
        begin
          if (w_TX_Ready && r_Wait_Count == 0)
          begin
            r_TX_Byte <= 8'h15;
            r_TX_DV   <= 1'b1;
            r_Wait_Count <= 1;
          end
          else if (r_Wait_Count > 0)
          begin
            r_Wait_Count <= r_Wait_Count + 1;
            if (r_Wait_Count == INIT_GYRO_TICKS)
            begin
              r_Wait_Count <= 0;
              r_State      <= ST_WAIT_SAMPLE;
            end
          end
        end

        ST_WAIT_SAMPLE:
        begin
          r_Wait_Count <= r_Wait_Count + 1;
          if (r_Wait_Count == SAMPLE_TICKS - 1)
          begin
            r_Wait_Count <= 0;
            r_State      <= ST_READ_GYRO;
          end
        end

        ST_READ_GYRO:
        begin
          if (w_TX_Ready)
          begin
            r_TX_Count <= 3'd7;
            r_TX_Byte  <= 8'h8C;
            r_TX_DV    <= 1'b1;
            r_State    <= ST_WAIT_GYRO_RX;
          end
        end

        ST_WAIT_GYRO_RX:
        begin
          if (w_TX_Ready && r_TX_DV == 0)
          begin
            r_TX_Byte <= 8'h00;
            r_TX_DV   <= 1'b1;
          end

          if (w_RX_DV)
          begin
            case (w_RX_Count)
              3'd1: r_GYR_X_L <= w_RX_Byte;
              3'd2: r_GYR_X_H <= w_RX_Byte;
              3'd3: r_GYR_Y_L <= w_RX_Byte;
              3'd4: r_GYR_Y_H <= w_RX_Byte;
              3'd5: r_GYR_Z_L <= w_RX_Byte;
              3'd6:
              begin
                r_GYR_Z_H <= w_RX_Byte;
                r_State   <= ST_READ_ACCEL;
              end
              default: ;
            endcase
          end
        end

        ST_READ_ACCEL:
        begin
          if (w_TX_Ready)
          begin
            r_TX_Count <= 3'd7;
            r_TX_Byte  <= 8'h92;
            r_TX_DV    <= 1'b1;
            r_State    <= ST_WAIT_ACCEL_RX;
          end
        end

        ST_WAIT_ACCEL_RX:
        begin
          if (w_TX_Ready && r_TX_DV == 0)
          begin
            r_TX_Byte <= 8'h00;
            r_TX_DV   <= 1'b1;
          end

          if (w_RX_DV)
          begin
            case (w_RX_Count)
              3'd1: r_ACC_X_L <= w_RX_Byte;
              3'd2: r_ACC_X_H <= w_RX_Byte;
              3'd3: r_ACC_Y_L <= w_RX_Byte;
              3'd4: r_ACC_Y_H <= w_RX_Byte;
              3'd5: r_ACC_Z_L <= w_RX_Byte;
              3'd6:
              begin
                r_ACC_Z_H <= w_RX_Byte;
                r_State   <= ST_STORE;
              end
              default: ;
            endcase
          end
        end

        ST_STORE:
        begin
          o_GYR_X <= {r_GYR_X_H, r_GYR_X_L};
          o_GYR_Y <= {r_GYR_Y_H, r_GYR_Y_L};
          o_GYR_Z <= {r_GYR_Z_H, r_GYR_Z_L};
          o_ACC_X <= {r_ACC_X_H, r_ACC_X_L};
          o_ACC_Y <= {r_ACC_Y_H, r_ACC_Y_L};
          o_ACC_Z <= {r_ACC_Z_H, r_ACC_Z_L};

          o_Data_Ready_Latch <= 1'b1;
          r_State <= ST_WAIT_SAMPLE;
        end

        default: r_State <= ST_INIT_ACCEL;
      endcase
    end
  end
endmodule


///////////////////////////////////////////////////////////////////////////////
// Decodificador MMIO
///////////////////////////////////////////////////////////////////////////////

module BMI160_MMIO
  (
    input        i_Clk,
    input        i_Rst_L,

    input  [31:0] mem_addr,
    input  [31:0] mem_wdata,
    input         mem_wen,
    output reg [31:0] mem_rdata,

    input [15:0] i_ACC_X, i_ACC_Y, i_ACC_Z,
    input [15:0] i_GYR_X, i_GYR_Y, i_GYR_Z,
    input        i_Data_Ready_Latch,
    output reg   o_Clear_Ready 
  );

  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      mem_rdata     <= 32'h0;
      o_Clear_Ready <= 1'b0;
    end
    else
    begin
      o_Clear_Ready <= 1'b0; 

      if (mem_addr[31:5] == 27'h2000000) 
      begin
        case (mem_addr[4:0])
          5'h00: mem_rdata <= {{16{i_ACC_X[15]}}, i_ACC_X};
          5'h04: mem_rdata <= {{16{i_ACC_Y[15]}}, i_ACC_Y};
          5'h08: mem_rdata <= {{16{i_ACC_Z[15]}}, i_ACC_Z};
          5'h0C: mem_rdata <= {{16{i_GYR_X[15]}}, i_GYR_X};
          5'h10: mem_rdata <= {{16{i_GYR_Y[15]}}, i_GYR_Y};
          5'h14: mem_rdata <= {{16{i_GYR_Z[15]}}, i_GYR_Z};
          5'h18: mem_rdata <= {31'b0, i_Data_Ready_Latch};
          default: mem_rdata <= 32'h0;
        endcase

        if (mem_addr[4:0] == 5'h18 && mem_wen)
          o_Clear_Ready <= 1'b1;
      end
    end
  end
endmodule
