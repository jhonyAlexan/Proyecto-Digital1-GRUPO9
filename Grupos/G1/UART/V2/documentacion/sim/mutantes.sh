#!/usr/bin/env bash
# G1 | Prueba de que el banco detecta errores: mete 5 fallas a proposito en
# copias del RTL y comprueba que tb_perip_mandos_filas.v las reporta.
# Uso: cd Grupos/G1/UART/V2/documentacion/sim && bash mutantes.sh
set -u
RTL=../rtl; TMP=$(mktemp -d)
correr() {
  iverilog -g2012 -o $TMP/m.vvp $TMP/uart_8n1.v $TMP/desempaquetador.v $TMP/perip_mandos.v tb_perip_mandos_filas.v || return
  if vvp -n $TMP/m.vvp | grep -q "RESULTADO: TODO OK"; then echo "  NO DETECTADA  <-- el banco no ve esta falla"; else echo "  detectada: $(vvp -n $TMP/m.vvp | grep RESULTADO)"; fi
}
limpiar() { cp $RTL/uart_8n1.v $RTL/desempaquetador.v $RTL/perip_mandos.v $TMP/; }
limpiar; sed -i 's/if (rx_data != xor_l) begin/if (1'"'"'b0) begin/' $TMP/desempaquetador.v
echo "M1 (D6) no se revisa el checksum";                    correr
limpiar; sed -i 's/p1_shield, p1_y, p1_x};/p1_shield, p1_x, p1_y};/' $TMP/perip_mandos.v
echo "M2 (B5) X e Y intercambiados en JOY1_DATA";            correr
limpiar; sed -i 's/r_sh  <= {rx_in, r_sh\[7:1\]};/r_sh  <= {r_sh[6:0], rx_in};/' $TMP/uart_8n1.v
echo "M3 (R7, R8) se recibe MSB primero";                   correr
limpiar; sed -i 's/if (espera == T_MAX_CICLOS - 1) begin/if (1'"'"'b0) begin/' $TMP/desempaquetador.v
echo "M4 (D11) no hay plazo de 1 ms";                       correr
limpiar; sed -i 's/R_ESPERA: if (rx_in) r_state <= R_IDLE;/R_ESPERA: r_state <= R_IDLE;/' $TMP/uart_8n1.v
echo "M5 (R11) no se espera la linea en 1 tras stop = 0";   correr
rm -rf $TMP
