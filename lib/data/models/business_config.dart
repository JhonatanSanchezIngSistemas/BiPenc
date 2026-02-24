class BusinessConfig {
  final String nombre;
  final String ruc;
  final String direccion;
  final String telefono;
  final String mensajeDespedida;

  BusinessConfig({
    required this.nombre,
    required this.ruc,
    required this.direccion,
    required this.telefono,
    this.mensajeDespedida = '¡Gracias por su compra!',
  });

  factory BusinessConfig.defaultConfig() {
    return BusinessConfig(
      nombre: 'Librería BiPenc',
      ruc: '00000000000',
      direccion: 'Ciudad Principal',
      telefono: '123456789',
      mensajeDespedida: '¡Vuelve pronto!',
    );
  }
}
