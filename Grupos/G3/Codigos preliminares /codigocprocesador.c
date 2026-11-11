#include <stdint.h>

// ── Registros MMIO del BMI160 ─────────────────────────────────────────────
#define IMU_BASE    0x40000000UL
#define IMU_ACC_X   (*((volatile int32_t*)(IMU_BASE + 0x00)))
#define IMU_ACC_Y   (*((volatile int32_t*)(IMU_BASE + 0x04)))
#define IMU_ACC_Z   (*((volatile int32_t*)(IMU_BASE + 0x08)))
#define IMU_GYR_X   (*((volatile int32_t*)(IMU_BASE + 0x0C)))
#define IMU_GYR_Y   (*((volatile int32_t*)(IMU_BASE + 0x10)))
#define IMU_GYR_Z   (*((volatile int32_t*)(IMU_BASE + 0x14)))
#define IMU_READY   (*((volatile int32_t*)(IMU_BASE + 0x18)))

// ── Resultado final para el otro grupo ────────────────────────────────────
// Dirección fija acordada en RAM donde el grupo Bluetooth lee el comando
#define RESULTADO   (*((volatile uint8_t*) 0x00001000UL))

// ── Umbrales trasladados al software ──────────────────────────────────────
#define UMBRAL_GYR2  160000L
#define UMBRAL_ACC2  25000000L

int main(void) {

    RESULTADO = 0x00;   // Inicializar flags en 0 antes del loop

    while (1) {
        // 1. Esperar dato fresco (handshake con el Verilog)
        while (IMU_READY == 0);

        // 2. Leer los 6 ejes del mapeo MMIO
        int16_t acc_x = (int16_t) IMU_ACC_X;
        int16_t acc_y = (int16_t) IMU_ACC_Y;
        int16_t acc_z = (int16_t) IMU_ACC_Z;
        int16_t gyr_x = (int16_t) IMU_GYR_X;
        int16_t gyr_y = (int16_t) IMU_GYR_Y;
        int16_t gyr_z = (int16_t) IMU_GYR_Z;

        // 3. Bajar el latch (esto escribe en 0x40000018 y activa o_Clear_Ready en la FPGA)
        IMU_READY = 0;

        // 4. Calcular magnitud² matemáticamente secuencial
        int32_t gyr_m2 = (int32_t)gyr_x * gyr_x
                       + (int32_t)gyr_y * gyr_y
                       + (int32_t)gyr_z * gyr_z;

        int32_t acc_m2 = (int32_t)acc_x * acc_x
                       + (int32_t)acc_y * acc_y
                       + (int32_t)acc_z * acc_z;

        // 5. Detectar ataque
        uint8_t flags = 0x00;
        
        // Rotación brusca combinada con movimiento fuerte
        if (gyr_m2 > UMBRAL_GYR2 && acc_m2 > UMBRAL_ACC2) {
            flags |= 0x01; // Bit 0 activo = Comando de Ataque
        }
        
        // Escribir en la memoria compartida
        RESULTADO = flags;
    }

    return 0;
}
