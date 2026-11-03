# Capsule Corp — Assets de oficina

44 PNG individuales: 35 props y 9 tiles de suelo. Todos los archivos de juego pesan menos de 80 KB.

## Archivos
- `props/`: paredes, ventana, rótulo, pantalla técnica, columna, lámpara, mesa, monitor, teclado, sillas, papelería, sofás, mesas auxiliares, alfombra, vitrina de las siete bolas, cocina, cafetera, expendedora, nevera, dispensador de agua, papelera, plantas, reloj, servidor y plataforma médica.
- `tiles/`: suelos azul, marfil y médico; líneas de circuito horizontal/vertical y cuatro esquinas.
- `catalogo_props.png`: vista de los 32 props iniciales y composiciones.
- `catalogo_tiles.png`: tiles ampliados para identificarlos.
- `manifest.json`: rutas, dimensiones, tamaño en bytes y anclajes.

## Colocación
Los suelos miden 32 × 32 px, igual que la cuadrícula del escenario. Los props conservan proporciones y tienen fondo transparente; su tamaño depende del objeto. El anclaje recomendado es inferior central, `[0.5, 1.0]`.

Para una pared larga: `wall_left`, repetir `wall_middle`, terminar con `wall_right`. Son tramos de 32 × 96 px. `wall_panel` ofrece la versión completa de 96 × 96 px. Colocar las ventanas, el rótulo y las pantallas sobre la pared.

`workstation_complete` incluye escritorio, monitor, teclado y papelería. Se entregan también sus componentes por separado: usar la composición o los componentes, según se necesite. La silla es independiente.

`coffee_counter_complete` combina mueble y cafetera; también se entregan por separado.

La alfombra y la plataforma médica van debajo de los personajes/objetos. Las sillas y sofás están vacíos. La colisión se configura al colocar los props según el espacio disponible.

Los personajes y la cápsula de recuperación existentes se conservan: no se han modificado ni reemplazado. Este paquete contiene los nuevos elementos del entorno. No se han cambiado archivos del proyecto ni instalado automáticamente los assets.

## Generación
Diseñados con el generador integrado de imágenes a partir de la propuesta Capsule Corp. Prompt común: pixel art RPG ortográfico, carcasa marfil, ribetes azules, acentos naranja y pantallas turquesa; objetos aislados con fondo transparente, sin personajes ni cápsula. Se generaron por familias (arquitectura, oficina, descanso, cocina y decoración), se separaron en PNG, se ajustaron de tamaño y se optimizaron sin pérdida. Los suelos se generaron en vista cenital; las esquinas adicionales son rotaciones de la misma pieza.
