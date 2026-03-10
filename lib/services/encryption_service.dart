import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bipenc/utils/app_logger.dart';

/// Servicio de encriptación AES-256-CBC para datos sensibles.
///
/// Usa [FlutterSecureStorage] para almacenar la master key de forma segura
/// en el KeyStore de Android / Keychain de iOS.
///
/// Uso:
/// ```dart
/// final enc = EncryptionService();
/// await enc.init();
/// final cifrado = enc.encriptar('dato secreto');
/// final original = enc.desencriptar(cifrado);
/// ```
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._();
  factory EncryptionService() => _instance;
  EncryptionService._();

  static const _keyName = 'bipenc_aes256_master_key';
  final _secureStorage = const FlutterSecureStorage();
  late encrypt.Key _masterKey;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Inicializa el servicio: genera o restaura la master key AES-256.
  Future<void> init() async {
    if (_initialized) return;

    try {
      String? keyString = await _secureStorage.read(key: _keyName);

      if (keyString == null) {
        // Generar nueva key de 256 bits (32 bytes)
        _masterKey = encrypt.Key.fromSecureRandom(32);
        await _secureStorage.write(
          key: _keyName,
          value: base64Url.encode(_masterKey.bytes),
        );
        AppLogger.info('[EncryptionService] ✅ Nueva master key generada');
      } else {
        _masterKey = encrypt.Key(base64Url.decode(keyString));
        AppLogger.info('[EncryptionService] ✅ Master key restaurada');
      }

      _initialized = true;
    } catch (e, stack) {
      AppLogger.critical(
        '[EncryptionService] 🔴 Error inicializando: $e',
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

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'EncryptionService no inicializado. Llama init() primero.',
      );
    }
  }
}
