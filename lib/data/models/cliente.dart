class Cliente {
  final String documento;
  final String nombre;
  final String? direccion;

  Cliente({
    required this.documento,
    required this.nombre,
    this.direccion,
  });

  Map<String, dynamic> toMap() {
    return {
      'documento': documento,
      'nombre': nombre,
      'direccion': direccion ?? '',
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      documento: map['documento'],
      nombre: map['nombre'],
      direccion: map['direccion'] == '' ? null : map['direccion'],
    );
  }
}
