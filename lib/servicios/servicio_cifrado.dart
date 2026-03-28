import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bipenc/utilidades/registro_app.dart';

/// Servicio de encriptación AES-256-CBC para datos sensibles.
///
/// Usa [FlutterSecureStorage] para almacenar la master key de forma segura
/// en el KeyStore de Android / Keychain de iOS.
///
/// Uso:
/// ```dart
/// final enc = ServicioCifrado();
/// await enc.init();
/// final cifrado = enc.encriptar('dato secreto');
/// final original = enc.desencriptar(cifrado);
/// ```
class ServicioCifrado {
  static final ServicioCifrado _instance = ServicioCifrado._();
  factory ServicioCifrado() => _instance;
  ServicioCifrado._();

  static const _keyName = 'bipenc_aes256_master_key';
  static const _blindIndexKeyName = 'bipenc_blind_index_key';
  final _secureStorage = const FlutterSecureStorage();
  late encrypt.Key _masterKey;
  late List<int> _blindIndexKey;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Inicializa el servicio: genera o restaura la master key AES-256.
  Future<void> init() async {
    if (_initialized) return;

    try {
      String? keyString = await _secureStorage.read(key: _keyName);
      String? blindKeyString = await _secureStorage.read(key: _blindIndexKeyName);

      if (keyString == null) {
        // Generar nueva key de 256 bits (32 bytes)
        _masterKey = encrypt.Key.fromSecureRandom(32);
        await _secureStorage.write(
          key: _keyName,
          value: base64Url.encode(_masterKey.bytes),
        );
        RegistroApp.info('[ServicioCifrado] ✅ Nueva master key generada');
      } else {
        _masterKey = encrypt.Key(base64Url.decode(keyString));
        RegistroApp.info('[ServicioCifrado] ✅ Master key restaurada');
      }

      if (blindKeyString == null) {
        final blindKey = encrypt.Key.fromSecureRandom(32);
        _blindIndexKey = blindKey.bytes;
        await _secureStorage.write(
          key: _blindIndexKeyName,
          value: base64Url.encode(_blindIndexKey),
        );
        RegistroApp.info('[ServicioCifrado] ✅ Blind index key generada');
      } else {
        _blindIndexKey = base64Url.decode(blindKeyString);
        RegistroApp.info('[ServicioCifrado] ✅ Blind index key restaurada');
      }

      _initialized = true;
    } catch (e, stack) {
      RegistroApp.critical(
        '[ServicioCifrado] 🔴 Error inicializando: $e',
        tag: 'ENCRYPTION',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Encripta un texto plano usando AES-256-CBC con IV aleatorio.
  ///
  /// Retorna string en formato: `iv_base64url.ciphertext_base64`
  /// El IV se genera aleatoriamente para cada operación.
  String encriptar(String plaintext) {
    _assertInitialized();

    final iv = encrypt.IV.fromSecureRandom(16);
    final cipher = encrypt.Encrypter(
      encrypt.AES(_masterKey, mode: encrypt.AESMode.cbc),
    );

    final encrypted = cipher.encrypt(plaintext, iv: iv);
    // Formato: iv_base64url.ciphertext_base64
    return '${base64Url.encode(iv.bytes)}.${encrypted.base64}';
  }

  /// Desencripta un texto cifrado producido por [encriptar].
  ///
  /// Espera formato: `iv_base64url.ciphertext_base64`
  /// Lanza [FormatException] si el formato es inválido.
  String desencriptar(String encrypted) {
    _assertInitialized();

    try {
      final parts = encrypted.split('.');
      if (parts.length != 2) {
        throw const FormatException(
          'Formato de texto cifrado inválido. Esperado: iv.ciphertext',
        );
      }

      final iv = encrypt.IV(base64Url.decode(parts[0]));
      final cipher = encrypt.Encrypter(
        encrypt.AES(_masterKey, mode: encrypt.AESMode.cbc),
      );

      return cipher.decrypt64(parts[1], iv: iv);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Error desencriptando: $e');
    }
  }

  /// Genera un blind index HMAC-SHA256 para búsquedas seguras.
  /// Útil para DNI/RUC: permite comparar igualdad sin exponer el valor real.
  String blindIndex(String value) {
    _assertInitialized();
    final normalized = value.trim();
    final hmac = Hmac(sha256, _blindIndexKey);
    final digest = hmac.convert(utf8.encode(normalized));
    return digest.toString();
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'ServicioCifrado no inicializado. Llama init() primero.',
      );
    }
  }
}
