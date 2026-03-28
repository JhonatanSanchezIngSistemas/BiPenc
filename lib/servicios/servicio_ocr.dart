import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR local basado en Google ML Kit.
/// Procesa completamente en dispositivo (privacidad y cero latencia de red).
class ServicioOcr {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Extrae líneas de texto legibles de la imagen.
  Future<List<String>> extraerLineas(File imageFile) async {
    final input = InputImage.fromFile(imageFile);
    final result = await _recognizer.processImage(input);
    return result.blocks
        .expand((b) => b.lines)
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> dispose() => _recognizer.close();
}
