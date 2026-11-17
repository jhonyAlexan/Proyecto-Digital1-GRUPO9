import serial
import struct
import math
import sys
# Codigo para leer datos en consola
# Cambiar a '/dev/ttyUSB0' si no se recibe datos en ttyUSB1, pero casi siempre por defecto es USB1
PUERTO = '/dev/ttyUSB1'
BAUDIOS = 115200

# Factores de escala por defecto del BMI160:
# Acelerómetro ±2g -> 16384 LSB/g (1g = 9.80665 m/s²)
ACCEL_SCALE = 9.80665 / 16384.0
# Giroscopio ±2000 °/s -> 16.4 LSB/(°/s)
GYRO_SCALE = 1.0 / 16.4

def hex16_to_signed(h):
    val = int(h, 16)
    return struct.unpack('>h', struct.pack('>H', val))[0]

def main():
    try:
        ser = serial.Serial(PUERTO, BAUDIOS, timeout=1)
        print(f"Conectado a {PUERTO} a {BAUDIOS} baudios. Presionar Ctrl+C para salir.\n")
    except Exception as e:
        print(f"Error abriendo {PUERTO}: {e}")
        print("Prueba cambiando PUERTO = '/dev/ttyUSB0' dentro del script.")
        sys.exit(1)

    while True:
        try:
            linea = ser.readline().decode('ascii', errors='ignore').strip()
            # Formato esperado: G:XXXX,YYYY,ZZZZ A:XXXX,YYYY,ZZZZ
            if linea.startswith("G:") and " A:" in linea:
                partes = linea.split(" A:")
                g_hex = partes[0][2:].split(",")
                a_hex = partes[1].split(",")

                if len(g_hex) == 3 and len(a_hex) == 3:
                    gx = hex16_to_signed(g_hex[0]) * GYRO_SCALE
                    gy = hex16_to_signed(g_hex[1]) * GYRO_SCALE
                    gz = hex16_to_signed(g_hex[2]) * GYRO_SCALE

                    ax = hex16_to_signed(a_hex[0]) * ACCEL_SCALE
                    ay = hex16_to_signed(a_hex[1]) * ACCEL_SCALE
                    az = hex16_to_signed(a_hex[2]) * ACCEL_SCALE

                    # Cálculo básico de inclinación (Roll y Pitch en grados)
                    roll  = math.degrees(math.atan2(ay, az))
                    pitch = math.degrees(math.atan2(-ax, math.sqrt(ay**2 + az**2)))

                    print(f"\rGyro [°/s]: X={gx:7.2f} Y={gy:7.2f} Z={gz:7.2f} | "
                          f"Accel [m/s²]: X={ax:6.2f} Y={ay:6.2f} Z={az:6.2f} | "
                          f"Roll={roll:6.1f}° Pitch={pitch:6.1f}°", end="", flush=True)

        except KeyboardInterrupt:
            print("\nLectura detenida.")
            ser.close()
            break
        except Exception:
            continue

if __name__ == "__main__":
    main()
