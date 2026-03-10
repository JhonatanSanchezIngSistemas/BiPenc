class BusinessConfig {
  final String nombre;
  final String ruc;
  final String direccion;
  final String telefono;
  final String mensajeDespedida;
  final String serie;

  BusinessConfig({
    required this.nombre,
    required this.ruc,
    required this.direccion,
    required this.telefono,
    this.mensajeDespedida = '¡Gracias por su compra!',
    this.serie = 'B001',
  });

  factory BusinessConfig.defaultConfig() {
    return BusinessConfig(
      nombre: 'Librería BiPenc',
      ruc: '00000000000',
      direccion: 'Ciudad Principal',
      telefono: '',
      mensajeDespedida: '¡Vuelve pronto!',
      serie: 'B001',
    );
  }
}
