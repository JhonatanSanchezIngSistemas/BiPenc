import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ServicioMlkit {
  ServicioMlkit() {
    debugPrint('[MLKit] Servicio de segmentación local inicializado');
  }

  Future<File?> segmentarProducto(String imagePath) async {
    try {
      final input = File(imagePath);
      if (!await input.exists()) return null;

      final bytes = await input.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final working = img.Image.from(decoded);
      final borderColor = _averageBorderColor(working);
      final transparent = img.ColorRgba8(0, 0, 0, 0);

      // Segmentación básica local:
      // 1) toma color promedio de bordes como fondo
      // 2) vuelve transparente lo similar al fondo
      for (int y = 0; y < working.height; y++) {
        for (int x = 0; x < working.width; x++) {
          final px = working.getPixel(x, y);
          if (_similar(px, borderColor, 48)) {
            working.setPixel(x, y, transparent);
          }
        }
      }

      final outDir = await getTemporaryDirectory();
      final outPath = '${outDir.path}/mlkit_seg_${DateTime.now().millisecondsSinceEpoch}.png';
      final out = File(outPath);
      await out.writeAsBytes(img.encodePng(working));

      debugPrint('[MLKit] Segmentación local completada: $outPath');
      return out;
    } catch (e) {
      debugPrint('[MLKit] Error segmentación: $e');
      return null;
    }
  }

  void dispose() {
    debugPrint('[MLKit] Service disposed');
  }

  img.Color _averageBorderColor(img.Image image) {
    int r = 0, g = 0, b = 0, count = 0;

    void addPixel(int x, int y) {
      final p = image.getPixel(x, y);
      r += p.r.toInt();
      g += p.g.toInt();
      b += p.b.toInt();
      count++;
    }

    for (int x = 0; x < image.width; x++) {
      addPixel(x, 0);
      addPixel(x, image.height - 1);
    }
    for (int y = 1; y < image.height - 1; y++) {
      addPixel(0, y);
      addPixel(image.width - 1, y);
    }

    if (count == 0) return img.ColorRgba8(255, 255, 255, 255);
    return img.ColorRgba8(r ~/ count, g ~/ count, b ~/ count, 255);
  }

  bool _similar(img.Color a, img.Color b, int tol) {
    return (a.r.toInt() - b.r.toInt()).abs() <= tol &&
        (a.g.toInt() - b.g.toInt()).abs() <= tol &&
        (a.b.toInt() - b.b.toInt()).abs() <= tol;
  }
}
