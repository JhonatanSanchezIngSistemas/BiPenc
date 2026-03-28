import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class ServicioActualizacion {
  static final SupabaseClient _supabase = Supabase.instance.client;

  bool get otaEnabled => _envBool('OTA_ENABLED', true);
  bool get strictVerification => _envBool('OTA_STRICT', false);
  bool get requireHash => _envBool('OTA_REQUIRE_HASH', true);

  /// Obtiene la versión actual de la aplicación desde pubspec.yaml (package_info)
  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return "${packageInfo.version}+${packageInfo.buildNumber}";
  }

  /// Consulta en Supabase si hay una versión más reciente
  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      if (!otaEnabled) return null;
      final currentVersion = await getCurrentVersion();
      
      final response = await _supabase
          .from('app_versions')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final latestVersion = response['version_code'] as String;
      
      if (_isVersionNewer(currentVersion, latestVersion)) {
        return response;
      }
    } catch (e) {
      debugPrint("Error checking for updates: $e");
    }
    return null;
  }

  ValidacionActualizacion validateUpdate(Map<String, dynamic> data) {
    final errors = <String>[];
    final warnings = <String>[];

    final rawUrl = (data['url_apk'] ?? '').toString().trim();
    if (rawUrl.isEmpty) {
      errors.add('URL de actualización vacía');
      return ValidacionActualizacion(errors: errors, warnings: warnings, uri: null, sha256: null);
    }

    Uri? uri;
    try {
      uri = Uri.parse(rawUrl);
      if (!uri.hasScheme || uri.scheme != 'https') {
        errors.add('La URL de actualización debe usar HTTPS');
      }
      final allowedHosts = _allowedHosts();
      if (allowedHosts.isNotEmpty && !allowedHosts.contains(uri.host)) {
        errors.add('Host no permitido para actualización');
      }
    } catch (_) {
      errors.add('URL de actualización inválida');
    }

    final sha = (data['sha256_apk'] ?? data['sha256'] ?? '').toString().trim();
    if (requireHash && sha.isEmpty) {
      errors.add('Falta SHA256 del APK');
    } else if (sha.isNotEmpty && !_isValidSha256(sha)) {
      warnings.add('SHA256 con formato inválido');
    }

    return ValidacionActualizacion(
      errors: errors,
      warnings: warnings,
      uri: uri,
      sha256: sha.isEmpty ? null : sha,
    );
  }

  /// Compara si la versión remota es mayor que la local
  bool _isVersionNewer(String current, String remote) {
    // Implementación simple comparando strings, pero idealmente se parsean los números
    // Formato esperado: X.Y.Z+B
    try {
      final currentParts = current.split('+');
      final remoteParts = remote.split('+');
      
      final currentVer = currentParts[0].split('.').map(int.parse).toList();
      final remoteVer = remoteParts[0].split('.').map(int.parse).toList();
      
      // Comparar versión semántica
      for (var i = 0; i < 3; i++) {
        final c = i < currentVer.length ? currentVer[i] : 0;
        final r = i < remoteVer.length ? remoteVer[i] : 0;
        if (r > c) return true;
        if (c > r) return false;
      }
      
      // Comparar build number si la versión es igual
      if (currentParts.length > 1 && remoteParts.length > 1) {
        return int.parse(remoteParts[1]) > int.parse(currentParts[1]);
      }
    } catch (e) {
      // Fallback a comparación de string si falla el parseo
      return current != remote;
    }
    return false;
  }

  /// Inicia el flujo de descarga e instalación
  Stream<OtaEvent> downloadAndInstall(String url) {
    try {
      return OtaUpdate().execute(
        url,
        destinationFilename: 'bipenc_update.apk',
      );
    } catch (e) {
      throw Exception("Error iniciando descarga: $e");
    }
  }

  Future<File> downloadAndVerifyApk({
    required Uri uri,
    required String expectedSha256,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'bipenc_update.apk'));
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Descarga fallida: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? -1;

      final digestSink = _ColectorHash();
      final digest = sha256.startChunkedConversion(digestSink);

      final sink = file.openWrite();
      int received = 0;

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          digest.add(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
        onError: (e) {
          throw Exception('Error descargando APK: $e');
        },
        cancelOnError: true,
      ).asFuture();

      await sink.close();
      digest.close();

      final actual = digestSink.value?.toString();
      if (actual == null || actual.isEmpty) {
        throw Exception('SHA256 no disponible');
      }
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        try {
          await file.delete();
        } catch (_) {}
        throw Exception('SHA256 no coincide');
      }
      return file;
    } finally {
      client.close();
    }
  }

  Stream<OtaEvent> installLocalApk(File file) {
    try {
      return OtaUpdate().execute(
        file.path,
        destinationFilename: p.basename(file.path),
      );
    } catch (e) {
      throw Exception("Error iniciando instalación local: $e");
    }
  }

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

  List<String> _allowedHosts() {
    final raw = _envString('OTA_ALLOWLIST').trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  bool _isValidSha256(String value) {
    final normalized = value.toLowerCase().trim();
    final reg = RegExp(r'^[a-f0-9]{64}$');
    return reg.hasMatch(normalized);
  }
}

class ValidacionActualizacion {
  final List<String> errors;
  final List<String> warnings;
  final Uri? uri;
  final String? sha256;

  bool get isValid => errors.isEmpty;

  const ValidacionActualizacion({
    required this.errors,
    required this.warnings,
    required this.uri,
    required this.sha256,
  });
}

class _ColectorHash implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
