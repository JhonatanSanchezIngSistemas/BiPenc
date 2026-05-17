// Alias de compatibilidad histórica.
//
// BiPenc migró su capa de base de datos local a `ServicioDbLocal`, pero algunos
// módulos aún importan `servicio_base_datos_local.dart`.
//
// Este archivo evita roturas de compilación y centraliza la fuente de verdad.
export 'package:bipenc/servicios/servicio_db_local.dart';
