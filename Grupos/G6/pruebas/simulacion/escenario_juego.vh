// Escenario de la simulacion del juego (firmware.hex): arranque, mandos y pelea.
esperar_cuadros(2); volcar("j1_inicio.txt");
ciclo_antes = ciclo; esperar_cuadros(1);
$display("ciclos por cuadro: %0d (presupuesto a 27 MHz: 450000)", ciclo - ciclo_antes);
mandos_on = 1; esperar_cuadros(4); volcar("j2_conectados.txt");
j1b = 1; esperar_cuadros(3); j1b = 0;  // boton del joystick de J1: empieza
esperar_cuadros(2);
j1x = 8'd127; esperar_cuadros(8); j1x = 8'd0; j1a = 1; esperar_cuadros(3); j1a = 0;
esperar_cuadros(2); volcar("j3_pelea.txt");
