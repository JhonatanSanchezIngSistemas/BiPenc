import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'servicio_db_local.dart';
import 'servicio_backend.dart';
import '../utilidades/registro_app.dart';

class ResultadoBusquedaDocumento {
  final String numero;
  final String nombre;
  final String? direccion;
  final String tipo; // DNI o RUC
  ResultadoBusquedaDocumento({
    required this.numero,
    required this.nombre,
    this.direccion,
    required this.tipo,
  });
}

class ServicioBusquedaDocumento {
  final Map<String, ResultadoBusquedaDocumento> _memCache = {};
  bool _purged = false;

  // --- Single-Flight ---
  final Map<String, Future<ResultadoBusquedaDocumento>> _activeRequests = {};

  // --- Circuit Breaker ---
  int _failureCount = 0;
  DateTime? _circuitOpenUntil;
  static const int _maxFailures = 3;
  static const Duration _circuitOpenDuration = Duration(seconds: 60);

  bool get _sharedCacheEnabled => _envBool('DOCUMENT_CACHE_SHARED', true);

  String _envString(String key) {
    final fromDefine = String.fromEnvironment(key);
    if (fromDefine.isNotEmpty) return fromDefine;
    return dotenv.env[key] ?? '';
  }

  bool _envBool(String key, bool fallback) {
    final raw = _envString(key).toLowerCase().trim();
    if (raw.isEmpty) return fallback;
    return raw == '1' || raw == 'true' || raw == 'yes';
  }

  Future<ResultadoBusquedaDocumento> lookup(String numero) async {
    final clean = numero.trim();
    RegistroApp.info('Iniciando lookup para: $clean', tag: 'DOC_LOOKUP');
    if (clean.length != 8 && clean.length != 11) {
      throw ArgumentError('Documento inválido');
    }

    final tipo = clean.length == 11 ? 'RUC' : 'DNI';

    if (!_purged) {
      _purged = true;
      unawaited(ServicioDbLocal.purgeExpiredDocuments());
    }

    // 1) RAM
    final mem = _memCache[clean];
    if (mem != null) {
      RegistroApp.debug('Memory cache hit: $clean', tag: 'DOC_LOOKUP');
      unawaited(ServicioDbLocal.registrarMetricaAPI(metodo: 'CACHE_MEMORIA', latencia: 0.0, exito: true));
      return mem;
    }

    // 2) SQLite
    final cachedRow = await ServicioDbLocal.getCachedDocument(clean);
    if (cachedRow != null) {
      final expiresAt = cachedRow['expires_at'] as int;
      if (expiresAt > DateTime.now().millisecondsSinceEpoch) {
        final res = ResultadoBusquedaDocumento(
          numero: clean,
          nombre: cachedRow['nombre'] as String,
          direccion: cachedRow['direccion'] as String?,
          tipo: cachedRow['tipo'] as String,
        );
        RegistroApp.debug('SQLite cache hit: $clean', tag: 'DOC_LOOKUP');
        unawaited(ServicioDbLocal.registrarMetricaAPI(metodo: 'CACHE_SQLITE', latencia: 0.0, exito: true));
        _memCache[clean] = res;
        unawaited(ServicioDbLocal.upsertClienteCache(
          numero: clean,
          nombre: res.nombre,
          direccion: res.direccion,
          tipo: res.tipo,
        ));
        return res;
      }
      RegistroApp.debug('SQLite cache expired for $clean', tag: 'DOC_LOOKUP');
    }

    // 2.5) Supabase cache compartido (opcional por sensibilidad de datos)
    if (_sharedCacheEnabled) {
      final remoteCache = await ServicioBackend.fetchDocumentoCache(clean);
      if (remoteCache != null) {
        final expiresAt = remoteCache['expires_at'] as int? ?? 0;
        if (expiresAt > DateTime.now().millisecondsSinceEpoch) {
          final res = ResultadoBusquedaDocumento(
            numero: clean,
            nombre: remoteCache['nombre'] as String,
            direccion: remoteCache['direccion'] as String?,
            tipo: remoteCache['tipo'] as String,
          );
          RegistroApp.info('Supabase cache hit: $clean', tag: 'DOC_LOOKUP');
          unawaited(ServicioDbLocal.registrarMetricaAPI(metodo: 'CACHE_SUPABASE', latencia: 0.0, exito: true));
          _memCache[clean] = res;
          await ServicioDbLocal.saveDocumentCache(
            numero: clean,
            tipo: res.tipo,
            nombre: res.nombre,
            direccion: res.direccion,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
          );
          return res;
        }
        RegistroApp.debug('Supabase cache expired for $clean', tag: 'DOC_LOOKUP');
      }
    }

    // 3) Red (con Circuit Breaker y Single-Flight)
    if (_circuitOpenUntil != null) {
      if (DateTime.now().isBefore(_circuitOpenUntil!)) {
        RegistroApp.warn('Circuit Breaker ABIERTO. Emitiendo fallback para $clean temporalmente.', tag: 'CIRCUIT_BREAKER');
        return _generateFallback(clean, tipo);
      } else {
        RegistroApp.info('Circuit Breaker CERRANDO (Half-Open). Intentando nueva solicitud.', tag: 'CIRCUIT_BREAKER');
        _circuitOpenUntil = null;
      }
    }

    if (_activeRequests.containsKey(clean)) {
      RegistroApp.debug('Single-Flight: uniéndose a petición en curso para $clean', tag: 'DOC_LOOKUP');
      return await _activeRequests[clean]!;
    }

    final future = _processRemoteLookup(clean, tipo);
    _activeRequests[clean] = future;

    try {
      return await future;
    } finally {
      _activeRequests.remove(clean);
    }
  }

  Future<ResultadoBusquedaDocumento> _processRemoteLookup(String clean, String tipo) async {
    RegistroApp.info('Buscando en API remota para $clean', tag: 'DOC_LOOKUP');
    final remote = await _fetchRemote(clean, tipo);
    
    if (remote != null) {
      _failureCount = 0; // Éxito
      _circuitOpenUntil = null;

      _memCache[clean] = remote;
      final expiresAt = _expiryForTipo(tipo);

      await ServicioDbLocal.saveDocumentCache(
        numero: clean,
        tipo: tipo,
        nombre: remote.nombre,
        direccion: remote.direccion,
        expiresAt: expiresAt,
      );

      // Guardar también en cache compartido Supabase (best effort); si falla, se encola para reconexión.
      if (_sharedCacheEnabled) {
        final pushed = await ServicioBackend.upsertDocumentoCache(
          numero: clean,
          tipo: tipo,
          nombre: remote.nombre,
          direccion: remote.direccion,
          expiresAtMs: expiresAt.millisecondsSinceEpoch,
        );

        if (!pushed) {
          await ServicioDbLocal.enqueueDocumentoCache({
            'numero': clean,
            'tipo': tipo,
            'nombre': remote.nombre,
            'direccion': remote.direccion,
            'cached_at': DateTime.now().millisecondsSinceEpoch,
            'expires_at': expiresAt.millisecondsSinceEpoch,
          });
        }
      }

      await ServicioDbLocal.upsertClienteCache(
        numero: clean,
        nombre: remote.nombre,
        direccion: remote.direccion,
        tipo: tipo,
      );
      RegistroApp.info('Lookup completado para $clean: ${remote.nombre}',
          tag: 'DOC_LOOKUP');
      return remote;
    }

    // Falló la red o la API
    _failureCount++;
    if (_failureCount >= _maxFailures) {
      _circuitOpenUntil = DateTime.now().add(_circuitOpenDuration);
      RegistroApp.error('Circuit Breaker ABIERTO debido a repetidos fallos (fallos: $_failureCount).', tag: 'CIRCUIT_BREAKER');
    }

    // Si falló, simplemente devolver un fallback temporal sin envenenar la base de datos
    RegistroApp.warn('Emitiendo fallback no cacheable para $clean', tag: 'DOC_LOOKUP');
    return _generateFallback(clean, tipo);
  }

  ResultadoBusquedaDocumento _generateFallback(String numero, String tipo) {
    return ResultadoBusquedaDocumento(
      numero: numero,
      nombre: 'Cliente $numero (Sin Conexión)',
      direccion: null,
      tipo: tipo,
    );
  }

  Duration _ttl(String tipo) => tipo == 'RUC'
      ? const Duration(days: 90) // 3 meses
      : const Duration(days: 180); // 6 meses

  DateTime _expiryForTipo(String tipo) => DateTime.now().add(_ttl(tipo));

  Future<ResultadoBusquedaDocumento?> _fetchRemote(String numero, String tipo) async {
    final token = _envString('APIS_NET_PE_TOKEN');

    if (token.isEmpty) {
      RegistroApp.warn(
        'APIS_NET_PE_TOKEN no configurado; lookup remoto deshabilitado',
        tag: 'DOC_LOOKUP',
      );
      return null;
    }

    final uri = tipo == 'RUC'
        ? Uri.parse('https://api.apis.net.pe/v1/ruc?numero=$numero')
        : Uri.parse('https://api.apis.net.pe/v1/dni?numero=$numero');

    bool iterExito = false;
    final stopwatch = Stopwatch()..start();
    try {
      RegistroApp.debug('Requesting remote: $uri', tag: 'DOC_LOOKUP');
      
      final timeoutStr = _envString('API_TIMEOUT_SECONDS');
      final timeoutSecs = int.tryParse(timeoutStr) ?? 10;
      
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(Duration(seconds: timeoutSecs));

      stopwatch.stop();
      RegistroApp.info('Latencia API: ${stopwatch.elapsedMilliseconds} ms para $numero', tag: 'LATENCY_METRIC');
      RegistroApp.debug('Response status: ${resp.statusCode}', tag: 'DOC_LOOKUP');

      if (resp.statusCode == 200) {
        iterExito = true;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (tipo == 'RUC') {
          final nombre = (data['razonSocial'] ??
                      data['razon_social'] ??
                      data['nombre'] ??
                      data['nombreComercial'] ??
                      data['nombre_comercial'])
                  ?.toString() ??
              'Cliente $numero';
          final direccion = (data['direccion'] ??
                  data['direccionCompleta'] ??
                  data['direccion_completa'])
              ?.toString();
          return ResultadoBusquedaDocumento(
            numero: numero,
            nombre: nombre,
            direccion: direccion,
            tipo: tipo,
          );
        } else {
          final fullName = (data['full_name'] ?? data['nombre_completo'] ?? '')
              .toString()
              .trim();
          final nombres = (data['nombres'] ??
                  data['nombres_completos'] ??
                  data['first_name'] ??
                  '')
              .toString()
              .trim();
          final apPat = (data['apellidoPaterno'] ??
                  data['apellido_paterno'] ??
                  data['first_last_name'] ??
                  '')
              .toString()
              .trim();
          final apMat = (data['apellidoMaterno'] ??
                  data['apellido_materno'] ??
                  data['second_last_name'] ??
                  '')
              .toString()
              .trim();
          final nombreCompleto =
              [nombres, apPat, apMat].where((e) => e.isNotEmpty).join(' ');

          final finalName = (fullName.isNotEmpty
                  ? fullName
                  : (nombreCompleto.trim().isNotEmpty
                      ? nombreCompleto.trim()
                      : 'Cliente $numero'))
              .toUpperCase();

          return ResultadoBusquedaDocumento(
            numero: numero,
            nombre: finalName,
            direccion: null,
            tipo: tipo,
          );
        }
      } else if (resp.statusCode == 401) {
        RegistroApp.error('API Error: 401 Unauthorized (DNI/RUC). Body: ${resp.body}',
            tag: 'DOC_LOOKUP');
      } else if (resp.statusCode == 429) {
        RegistroApp.warn('API Error: 429 Too Many Requests', tag: 'DOC_LOOKUP');
      } else {
        RegistroApp.warn('API Error: ${resp.statusCode} - ${resp.body}',
            tag: 'DOC_LOOKUP');
      }
    } catch (e, st) {
      RegistroApp.error('Excepción en fetchRemote: $e',
          tag: 'DOC_LOOKUP', error: e, stackTrace: st);
    } finally {
      if (stopwatch.isRunning) stopwatch.stop();
      final lat = stopwatch.elapsedMilliseconds / 1000.0;
      unawaited(ServicioDbLocal.registrarMetricaAPI(
        metodo: 'API_APIS_NET_PE',
        latencia: lat,
        exito: iterExito,
      ));
    }

    return null;
  }
}
