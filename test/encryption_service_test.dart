import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Tests para la lógica de encriptación AES-256-CBC.
///
/// Nota: No podemos testear [EncryptionService] directamente porque
/// depende de [FlutterSecureStorage] (nativo). En su lugar, testeamos
/// la lógica pura de AES que el servicio usa internamente.
void main() {
  group('AES-256-CBC Encryption Logic', () {
    late encrypt.Key masterKey;

    setUp(() {
      masterKey = encrypt.Key.fromSecureRandom(32);
    });

    String encriptar(String plaintext) {
      final iv = encrypt.IV.fromSecureRandom(16);
      final cipher = encrypt.Encrypter(
        encrypt.AES(masterKey, mode: encrypt.AESMode.cbc),
      );
      final encrypted = cipher.encrypt(plaintext, iv: iv);
      return '${base64Url.encode(iv.bytes)}.${encrypted.base64}';
    }

    String desencriptar(String encrypted) {
      final parts = encrypted.split('.');
      if (parts.length != 2) throw const FormatException('Formato inválido');
      final iv = encrypt.IV(base64Url.decode(parts[0]));
      final cipher = encrypt.Encrypter(
        encrypt.AES(masterKey, mode: encrypt.AESMode.cbc),
      );
      return cipher.decrypt64(parts[1], iv: iv);
    }

    test('Encrypt y decrypt round-trip devuelve el texto original', () {
      const plaintext = 'datos_sensibles_token_jwt_123';
      final encrypted = encriptar(plaintext);
      final decrypted = desencriptar(encrypted);
      expect(decrypted, plaintext);
    });

    test('Texto cifrado difiere del texto plano', () {
      const plaintext = 'mi_contraseña_secreta';
      final encrypted = encriptar(plaintext);
      expect(encrypted, isNot(equals(plaintext)));
    });

    test('Diferentes encriptaciones producen diferentes ciphertexts (random IV)', () {
      const plaintext = 'mismo_texto';
      final encrypted1 = encriptar(plaintext);
      final encrypted2 = encriptar(plaintext);
      expect(encrypted1, isNot(equals(encrypted2)));

      // Pero ambos desencriptan al mismo valor
      expect(desencriptar(encrypted1), plaintext);
      expect(desencriptar(encrypted2), plaintext);
    });

    test('Formato inválido lanza FormatException', () {
      expect(
        () => desencriptar('texto_sin_punto'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Encripta y desencripta texto largo (JSON token)', () {
      const token =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      final encrypted = encriptar(token);
      final decrypted = desencriptar(encrypted);
      expect(decrypted, token);
    });

    test('Encripta y desencripta texto con caracteres especiales', () {
      const textoEspecial = 'Contraseña: María@2026! ñ ü é';
      final encrypted = encriptar(textoEspecial);
      final decrypted = desencriptar(encrypted);
      expect(decrypted, textoEspecial);
    });

    test('Diferentes keys no pueden desencriptar', () {
      const plaintext = 'dato_secreto';
      final encrypted = encriptar(plaintext);

      // Crear nueva key diferente
      final otherKey = encrypt.Key.fromSecureRandom(32);
      final otherCipher = encrypt.Encrypter(
        encrypt.AES(otherKey, mode: encrypt.AESMode.cbc),
      );

      final parts = encrypted.split('.');
      final iv = encrypt.IV(base64Url.decode(parts[0]));

      // AES con key incorrecta puede lanzar excepción o retornar texto basura.
      expect(
        () => otherCipher.decrypt64(parts[1], iv: iv),
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );
    });
  });
}
