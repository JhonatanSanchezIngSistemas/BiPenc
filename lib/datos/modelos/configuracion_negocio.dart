class ConfiguracionNegocio {
  final String nombre;
  final String ruc;
  final String direccion;
  final String telefono;
  final String mensajeDespedida;
  final String serie;

  ConfiguracionNegocio({
    required this.nombre,
    required this.ruc,
    required this.direccion,
    required this.telefono,
    this.mensajeDespedida = '¡Gracias por su compra!',
    this.serie = 'B001',
  });

  factory ConfiguracionNegocio.defaultConfig() {
    return ConfiguracionNegocio(
      nombre: 'Librería BiPenc',
      ruc: '00000000000',
      direccion: 'Ciudad Principal',
      telefono: '',
      mensajeDespedida: '¡Vuelve pronto!',
      serie: 'B001',
    );
  }
}
