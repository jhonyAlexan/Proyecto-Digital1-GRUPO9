// Escenario de la simulacion de pruebas.hex: que hacen los mandos y los botones,
// y cuando se guardan los cuadros.
esperar_cuadros(2); volcar("p1_pantalla.txt");
ciclo_antes = ciclo; esperar_cuadros(1);
$display("ciclos por cuadro: %0d", ciclo - ciclo_antes);
j1x = 8'd127; j1y = 8'd0; j1b = 1; j2x = 8'hC4; j2y = 8'd100; j2a = 1; mandos_on = 1;
botones = 4'b0100;
esperar_cuadros(4);
$display("J1 mantiene el boton: debe pasar a la prueba 2");
esperar_cuadros(6);
joy_estado = joy_estado | 32'h8;  // el periferico marca un error de checksum
esperar_cuadros(2); volcar("p2_entradas.txt");
$display("LED con el boton de J1 oprimido: %0d", led);
j1b = 0; botones = 4'b0000; esperar_cuadros(3);
botones = 4'b0001; esperar_cuadros(2); botones = 4'b0000;  // boton 1: prueba 3
esperar_cuadros(17); volcar("p3_sonido.txt");
botones = 4'b0001; esperar_cuadros(2); botones = 4'b0000; esperar_cuadros(2); volcar("p4_vuelve.txt");
