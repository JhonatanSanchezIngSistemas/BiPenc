import 'dart:async';

/// REFACTOR: Stub seguro para Yape; el listener se eliminó por inestabilidad del plugin.
class ServicioYape {
  static final ServicioYape _instance = ServicioYape._();
  factory ServicioYape() => _instance;
  ServicioYape._();

  final _controller = StreamController<EventoYape>.broadcast();
  Stream<EventoYape> get stream => _controller.stream;

  Future<void> start() async {
    // No-op intencional. Mantener firma pública para evitar romper dependencias.
  }

  void stop() {}

  void dispose() {
    _controller.close();
  }
}

class EventoYape {
  final String nombre;
  final double? monto;
  const EventoYape({required this.nombre, this.monto});
}
